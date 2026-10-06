import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

@main
struct CandidateDeliverySnapshotCheck {
    static func main() async throws {
        stateSnapshotUsesAssemblerForConfirmedVolatileBoundary()
        try await waitsForDelayedProviderTailBeforeDelivery()
        try await preservesLegacyPreviewDeliveryText()
        print("CandidateDeliverySnapshotCheck passed")
    }

    private static func stateSnapshotUsesAssemblerForConfirmedVolatileBoundary() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let state = TranscriptState(
            sessionID: sessionID,
            providerEpoch: 1,
            lastSequence: 2,
            confirmedSegments: [
                TranscriptSegment(
                    id: "confirmed",
                    text: "用户体验",
                    audioRange: TranscriptionAudioRange(start: 0, end: 1)
                )
            ],
            volatileSegmentID: "tail",
            volatileRevision: 1,
            volatileText: "体验不要了吗",
            lifecycle: .completed,
            failure: nil,
            connectionState: .connected
        )

        let snapshot = CandidateDeliverySnapshot(state: state)
        precondition(snapshot.text == "用户体验不要了吗")
        precondition(!snapshot.text.contains("体验体验"))
    }

    private static func preservesLegacyPreviewDeliveryText() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let runtime = ShadowTranscriptionRuntime(sessionID: sessionID)
        try await runtime.start()

        let displaySnapshot = PreviewDisplaySnapshot(
            revision: 1,
            stableCharacterCount: 4,
            stableWindowText: "已经稳定",
            volatileTailText: "正在说的尾巴"
        )
        await runtime.consume(
            displaySnapshot,
            completeTranscript: CompleteTranscriptSnapshot(
                revision: 1,
                stableText: "已经稳定",
                volatileTailText: "正在说的尾巴",
                lifecycle: .running,
                sourceIdentity: "test-legacy"
            )
        )

        let beforeComplete = await runtime.deliverySnapshot()
        precondition(beforeComplete.text == "已经稳定正在说的尾巴")
        precondition(beforeComplete.source == .realtimePreviewDeliveryCache)
        precondition(beforeComplete.isUsable(languageMode: .chinese))

        let afterComplete = await runtime.completeForDelivery()
        precondition(afterComplete.text == "已经稳定正在说的尾巴")
        precondition(afterComplete.source == .realtimePreviewDeliveryCache)
        precondition(afterComplete.isUsable(languageMode: .chinese))

        let emptyRuntime = ShadowTranscriptionRuntime(sessionID: TranscriptionSessionID(rawValue: UUID()))
        try await emptyRuntime.start()
        let empty = await emptyRuntime.completeForDelivery()
        precondition(!empty.isUsable(languageMode: .chinese))
    }

    private static func waitsForDelayedProviderTailBeforeDelivery() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let provider = DelayedFinishProvider()
        let runtime = ShadowTranscriptionRuntime(sessionID: sessionID, provider: provider)
        try await runtime.start()

        let snapshot = await runtime.completeForDelivery(timeoutNanoseconds: 300_000_000)
        precondition(snapshot.text == "最后一句补上了")
        precondition(snapshot.lifecycle == .completed)
        precondition(snapshot.isDeliverable(languageMode: .chinese))

        let hangingRuntime = ShadowTranscriptionRuntime(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: HangingFinishProvider()
        )
        try await hangingRuntime.start()
        let hanging = await hangingRuntime.completeForDelivery(timeoutNanoseconds: 80_000_000)
        precondition(hanging.text == "未完成的尾巴")
        precondition(hanging.lifecycle == .running)
        precondition(hanging.isUsable(languageMode: .chinese))
        precondition(!hanging.isDeliverable(languageMode: .chinese))
    }
}

private final class DelayedFinishProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "delayed-finish"
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )

    private let lock = NSLock()
    private let stream: AsyncStream<TranscriptionEvent>
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var sessionID: TranscriptionSessionID?
    private var providerEpoch = 0

    init() {
        var captured: AsyncStream<TranscriptionEvent>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        continuation = captured
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        lock.withLock {
            self.sessionID = sessionID
            self.providerEpoch = providerEpoch
        }
    }

    func append(_ frame: AudioFrame) async throws {}

    func finish() async throws {
        let captured: (TranscriptionSessionID, Int, AsyncStream<TranscriptionEvent>.Continuation?)? = lock.withLock {
            guard let sessionID else { return nil }
            return (sessionID, providerEpoch, continuation)
        }
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let (sessionID, epoch, continuation) = captured else { return }
            continuation?.yield(.partial(
                metadata(sessionID, epoch: epoch, sequence: 1),
                segmentID: "tail",
                revision: 1,
                text: "最后一句补上了"
            ))
            continuation?.yield(.completed(metadata(sessionID, epoch: epoch, sequence: 2)))
            continuation?.finish()
        }
    }

    func cancel() async {
        continuation?.finish()
    }

    func events() -> AsyncStream<TranscriptionEvent> {
        stream
    }

    private func metadata(
        _ sessionID: TranscriptionSessionID,
        epoch: Int,
        sequence: UInt64
    ) -> TranscriptionEventMetadata {
        TranscriptionEventMetadata(
            sessionID: sessionID,
            providerEpoch: epoch,
            sequence: sequence,
            emittedAtUptime: TimeInterval(sequence)
        )
    }
}

private final class HangingFinishProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "hanging-finish"
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )

    private let stream: AsyncStream<TranscriptionEvent>
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var sessionID: TranscriptionSessionID?
    private var providerEpoch = 0

    init() {
        var captured: AsyncStream<TranscriptionEvent>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        continuation = captured
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        self.sessionID = sessionID
        self.providerEpoch = providerEpoch
    }

    func append(_ frame: AudioFrame) async throws {}

    func finish() async throws {
        guard let sessionID else { return }
        continuation?.yield(.partial(
            metadata(sessionID, epoch: providerEpoch, sequence: 1),
            segmentID: "tail",
            revision: 1,
            text: "未完成的尾巴"
        ))
    }

    func cancel() async {
        continuation?.finish()
    }

    func events() -> AsyncStream<TranscriptionEvent> {
        stream
    }

    private func metadata(
        _ sessionID: TranscriptionSessionID,
        epoch: Int,
        sequence: UInt64
    ) -> TranscriptionEventMetadata {
        TranscriptionEventMetadata(
            sessionID: sessionID,
            providerEpoch: epoch,
            sequence: sequence,
            emittedAtUptime: TimeInterval(sequence)
        )
    }
}
