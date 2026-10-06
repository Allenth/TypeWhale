import Foundation

enum FakeStreamingEmission: Equatable, Sendable {
    case partial(segmentID: String, revision: Int, text: String)
    case finalized(TranscriptSegment)
    case connectionChanged(ProviderConnectionState)
    case failed(TranscriptionFailure)
    case completed
    case cancelled
}

struct FakeStreamingScriptStep: Equatable, Sendable {
    let emission: FakeStreamingEmission
    let delayNanoseconds: UInt64?
    let providerEpochOffset: Int

    init(
        emission: FakeStreamingEmission,
        delayNanoseconds: UInt64? = nil,
        providerEpochOffset: Int = 0
    ) {
        self.emission = emission
        self.delayNanoseconds = delayNanoseconds
        self.providerEpochOffset = providerEpochOffset
    }
}

enum FakeStreamingFailureInjection: Equatable, Sendable {
    case none
    case start
    case append(afterAcceptedFrameCount: Int)
    case finish
}

enum FakeStreamingProviderError: Error, Equatable {
    case injectedStartFailure
    case injectedAppendFailure
    case injectedFinishFailure
}

/// 确定性的流式 Provider 测试替身。
///
/// 它只消费连续 `AudioFrame` 并产生统一事件，不依赖任何界面组件。
final class FakeStreamingProvider: TranscriptionProvider, @unchecked Sendable {
    let id: String
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )

    private let script: [FakeStreamingScriptStep]
    private let defaultDelayNanoseconds: UInt64
    private let failureInjection: FakeStreamingFailureInjection
    private let lock = NSLock()
    private let eventStream: AsyncStream<TranscriptionEvent>
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var scriptTask: Task<Void, Never>?
    private var acceptedFrameCount = 0

    init(
        id: String,
        script: [FakeStreamingScriptStep],
        defaultDelayNanoseconds: UInt64 = 0,
        failureInjection: FakeStreamingFailureInjection = .none
    ) {
        self.id = id
        self.script = script
        self.defaultDelayNanoseconds = defaultDelayNanoseconds
        self.failureInjection = failureInjection
        var captured: AsyncStream<TranscriptionEvent>.Continuation?
        eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) {
            captured = $0
        }
        continuation = captured
    }

    var receivedFrameCount: Int {
        lock.withLock { acceptedFrameCount }
    }

    func start(
        sessionID: TranscriptionSessionID,
        providerEpoch: Int
    ) async throws {
        if failureInjection == .start {
            throw FakeStreamingProviderError.injectedStartFailure
        }
        let prior = lock.withLock { () -> Task<Void, Never>? in
            let prior = scriptTask
            scriptTask = makeScriptTask(
                sessionID: sessionID,
                providerEpoch: providerEpoch
            )
            return prior
        }
        prior?.cancel()
    }

    func append(_ frame: AudioFrame) async throws {
        let shouldFail = lock.withLock { () -> Bool in
            if case .append(let threshold) = failureInjection,
               acceptedFrameCount >= threshold {
                return true
            }
            acceptedFrameCount += 1
            return false
        }
        if shouldFail {
            throw FakeStreamingProviderError.injectedAppendFailure
        }
    }

    func finish() async throws {
        if failureInjection == .finish {
            throw FakeStreamingProviderError.injectedFinishFailure
        }
    }

    func cancel() async {
        close()
    }

    func events() -> AsyncStream<TranscriptionEvent> {
        eventStream
    }

    private func makeScriptTask(
        sessionID: TranscriptionSessionID,
        providerEpoch: Int
    ) -> Task<Void, Never> {
        let steps = script
        let defaultDelay = defaultDelayNanoseconds
        return Task { [weak self] in
            var sequence: UInt64 = 0
            for step in steps {
                let delay = step.delayNanoseconds ?? defaultDelay
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled, let self else { return }
                sequence += 1
                let metadata = TranscriptionEventMetadata(
                    sessionID: sessionID,
                    providerEpoch: providerEpoch + step.providerEpochOffset,
                    sequence: sequence,
                    emittedAtUptime: ProcessInfo.processInfo.systemUptime
                )
                self.yield(step.emission.event(metadata: metadata))
            }
        }
    }

    private func yield(_ event: TranscriptionEvent) {
        let target = lock.withLock { continuation }
        target?.yield(event)
    }

    private func close() {
        let pair = lock.withLock { () -> (
            Task<Void, Never>?,
            AsyncStream<TranscriptionEvent>.Continuation?
        ) in
            let pair = (scriptTask, continuation)
            scriptTask = nil
            continuation = nil
            return pair
        }
        pair.0?.cancel()
        pair.1?.finish()
    }
}

private extension FakeStreamingEmission {
    func event(metadata: TranscriptionEventMetadata) -> TranscriptionEvent {
        switch self {
        case .partial(let segmentID, let revision, let text):
            return .partial(
                metadata,
                segmentID: segmentID,
                revision: revision,
                text: text
            )
        case .finalized(let segment):
            return .finalized(metadata, segment: segment)
        case .connectionChanged(let state):
            return .connectionChanged(metadata, state)
        case .failed(let failure):
            return .failed(metadata, failure)
        case .completed:
            return .completed(metadata)
        case .cancelled:
            return .cancelled(metadata)
        }
    }
}
