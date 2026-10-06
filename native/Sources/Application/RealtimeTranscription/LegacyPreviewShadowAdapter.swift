import Foundation

/// 将生产预览的只读展示快照翻译成统一转录事件。
///
/// 该适配器只维护旁路事件身份与稳定边界，不调用旧识别链路，也不写回生产状态。
struct LegacyPreviewShadowAdapter: Sendable {
    private let sessionID: TranscriptionSessionID
    private let providerEpoch: Int
    private var sequence: UInt64 = 0
    private var stableCharacterCount = 0
    private var volatileText = ""
    private var volatileRevision = 0
    private var segmentIndex = 0
    private var isTerminal = false

    init(sessionID: TranscriptionSessionID, providerEpoch: Int) {
        self.sessionID = sessionID
        self.providerEpoch = providerEpoch
    }

    mutating func consume(_ snapshot: PreviewDisplaySnapshot) -> [TranscriptionEvent] {
        guard !isTerminal else { return [] }
        guard snapshot.stableCharacterCount >= stableCharacterCount else {
            return [failure(
                "legacy stable boundary regressed from \(stableCharacterCount) to \(snapshot.stableCharacterCount)"
            )]
        }

        var events: [TranscriptionEvent] = []
        if snapshot.stableCharacterCount > stableCharacterCount {
            let promotedCount = snapshot.stableCharacterCount - stableCharacterCount
            let promotedText = String(snapshot.stableWindowText.suffix(promotedCount))
            events.append(.finalized(
                nextMetadata(),
                segment: TranscriptSegment(
                    id: currentSegmentID,
                    text: promotedText,
                    audioRange: TranscriptionAudioRange(start: 0, end: 0)
                )
            ))
            stableCharacterCount = snapshot.stableCharacterCount
            segmentIndex += 1
            volatileRevision = 0
            volatileText = ""
        }

        if snapshot.volatileTailText != volatileText {
            volatileRevision += 1
            volatileText = snapshot.volatileTailText
            events.append(.partial(
                nextMetadata(),
                segmentID: currentSegmentID,
                revision: volatileRevision,
                text: volatileText
            ))
        }
        return events
    }

    mutating func complete() -> [TranscriptionEvent] {
        terminalEvent { .completed($0) }
    }

    mutating func cancel() -> [TranscriptionEvent] {
        terminalEvent { .cancelled($0) }
    }

    private var currentSegmentID: String {
        "legacy-\(segmentIndex)"
    }

    private mutating func nextMetadata() -> TranscriptionEventMetadata {
        sequence += 1
        return TranscriptionEventMetadata(
            sessionID: sessionID,
            providerEpoch: providerEpoch,
            sequence: sequence,
            emittedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private mutating func failure(_ message: String) -> TranscriptionEvent {
        .failed(
            nextMetadata(),
            TranscriptionFailure(
                code: .internalInvariant,
                message: message,
                isRecoverable: true
            )
        )
    }

    private mutating func terminalEvent(
        _ makeEvent: (TranscriptionEventMetadata) -> TranscriptionEvent
    ) -> [TranscriptionEvent] {
        guard !isTerminal else { return [] }
        isTerminal = true
        return [makeEvent(nextMetadata())]
    }
}

final class LegacyPreviewShadowProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "legacy-preview-shadow"
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: false,
        supportsPartialResults: true,
        supportsServerFinalization: false,
        maximumConcurrentSessions: 1
    )

    private let lock = NSLock()
    private let stream: AsyncStream<TranscriptionEvent>
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?

    init() {
        var captured: AsyncStream<TranscriptionEvent>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        continuation = captured
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {}
    func append(_ frame: AudioFrame) async throws {
        throw TranscriptionSessionError.terminal
    }
    func finish() async throws {}
    func cancel() async { close() }
    func events() -> AsyncStream<TranscriptionEvent> { stream }

    func send(_ events: [TranscriptionEvent]) {
        lock.lock()
        let target = continuation
        lock.unlock()
        for event in events { target?.yield(event) }
    }

    func close() {
        lock.lock()
        let target = continuation
        continuation = nil
        lock.unlock()
        target?.finish()
    }
}

enum CandidateDeliverySnapshotSource: String, Sendable {
    case candidatePreviewCache = "candidate-preview-cache"
    case shadowRuntimeCache = "shadow-runtime-cache"
    case legacyCandidateAdapter = "legacy-candidate-adapter"
    case realtimePreviewDeliveryCache = "realtime-preview-delivery-cache"
}

struct CandidateDeliverySnapshot: Equatable, Sendable {
    let text: String
    let source: CandidateDeliverySnapshotSource
    let lifecycle: TranscriptionLifecycle

    init(
        text: String,
        source: CandidateDeliverySnapshotSource = .candidatePreviewCache,
        lifecycle: TranscriptionLifecycle
    ) {
        self.text = text
        self.source = source
        self.lifecycle = lifecycle
    }

    init(
        state: TranscriptState,
        source: CandidateDeliverySnapshotSource = .shadowRuntimeCache
    ) {
        self.init(
            text: TranscriptSnapshotAssembler.deliveryText(
                confirmed: state.confirmedText,
                volatile: state.volatileText
            ),
            source: source,
            lifecycle: state.lifecycle
        )
    }

    func isUsable(languageMode: RecognitionLanguageMode) -> Bool {
        isMeaningfulRecognitionText(cleanRecognitionText(text, languageMode: languageMode))
    }

    func isDeliverable(languageMode: RecognitionLanguageMode) -> Bool {
        lifecycle == .completed && isUsable(languageMode: languageMode)
    }

    static func selectForFinalDelivery(
        shadowRuntimeSnapshot: CandidateDeliverySnapshot?,
        realtimePreviewDeliverySnapshot: CandidateDeliverySnapshot?,
        languageMode: RecognitionLanguageMode
    ) -> CandidateDeliverySnapshot? {
        guard let realtimePreviewDeliverySnapshot,
              realtimePreviewDeliverySnapshot.isDeliverable(languageMode: languageMode) else {
            return nil
        }
        return realtimePreviewDeliverySnapshot
    }
}

actor ShadowTranscriptionRuntime {
    static let technicalVisibleCharacterLimit = 160
    static let candidateVisibleCharacterLimit = 4096

    private var adapter: LegacyPreviewShadowAdapter?
    private let legacyProvider: LegacyPreviewShadowProvider?
    private let session: TranscriptionSession
    private let consumesPCM: Bool
    private var realtimePreviewDeliveryCache = RealtimePreviewDeliveryCache()

    init(sessionID: TranscriptionSessionID) {
        let provider = LegacyPreviewShadowProvider()
        legacyProvider = provider
        adapter = LegacyPreviewShadowAdapter(sessionID: sessionID, providerEpoch: 1)
        session = TranscriptionSession(sessionID: sessionID, provider: provider)
        consumesPCM = false
    }

    init(
        sessionID: TranscriptionSessionID,
        provider: any TranscriptionProvider
    ) {
        legacyProvider = nil
        adapter = nil
        session = TranscriptionSession(sessionID: sessionID, provider: provider)
        consumesPCM = true
    }

    func start() async throws {
        try await session.start()
    }

    func states(
        visibleCharacterLimit: Int = technicalVisibleCharacterLimit
    ) async -> AsyncStream<PreviewViewState> {
        let source = await session.states()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await state in source {
                    guard !Task.isCancelled else { return }
                    continuation.yield(PreviewStateProjector.project(
                        state,
                        visibleCharacterLimit: visibleCharacterLimit
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func deliverySnapshot() async -> CandidateDeliverySnapshot {
        if let legacySnapshot = realtimePreviewDeliveryCache.deliverySnapshot() {
            return legacySnapshot
        }
        return CandidateDeliverySnapshot(state: await session.currentState(), source: .shadowRuntimeCache)
    }

    func completeForDelivery(
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async -> CandidateDeliverySnapshot {
        await complete()
        if legacyProvider == nil {
            await waitForDeliveryCompletion(timeoutNanoseconds: timeoutNanoseconds)
        }
        return await deliverySnapshot()
    }

    private func waitForDeliveryCompletion(timeoutNanoseconds: UInt64) async {
        let stepNanoseconds: UInt64 = 10_000_000
        let maxAttempts = max(1, Int(timeoutNanoseconds / stepNanoseconds))
        for _ in 0..<maxAttempts {
            let state = await session.currentState()
            if state.lifecycle.isTerminal { return }
            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }
    }

    func consumesAudioFrames() -> Bool { consumesPCM }

    func append(_ frame: AudioFrame) async throws {
        guard consumesPCM else { return }
        try await session.append(frame)
    }

    func consume(
        _ snapshot: PreviewDisplaySnapshot,
        completeTranscript: CompleteTranscriptSnapshot
    ) {
        guard var adapter, let legacyProvider else { return }
        let events = adapter.consume(snapshot)
        legacyProvider.send(events)
        self.adapter = adapter
        if events.contains(where: { event in
            if case .failed = event { return true }
            return false
        }) {
            return
        }
        realtimePreviewDeliveryCache.consume(completeTranscript)
    }

    func complete() async {
        if var adapter, let legacyProvider {
            legacyProvider.send(adapter.complete())
            legacyProvider.close()
            self.adapter = adapter
            realtimePreviewDeliveryCache.complete()
        } else {
            await session.finish()
        }
    }

    func cancel() async {
        if var adapter, let legacyProvider {
            legacyProvider.send(adapter.cancel())
            legacyProvider.close()
            self.adapter = adapter
        } else {
            await session.cancel()
        }
    }
}
