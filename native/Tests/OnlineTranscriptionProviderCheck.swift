import Foundation

@main
struct OnlineTranscriptionProviderCheck {
    static func main() async throws {
        try await successfulFinishIsOrderedTerminalAndLeakFree()
        try await successfulFinishCompletesRealSession()
        try await cancelWinsBeforeServerCompletion()
        print("OnlineTranscriptionProviderCheck passed")
    }

    private static func successfulFinishIsOrderedTerminalAndLeakFree() async throws {
        let transport = FixtureOnlineStreamingTransport(
            finishBehavior: .completeWithDuplicateAndLateMessages
        )
        let provider = OnlineTranscriptionProvider(id: "online-fixture", transport: transport)
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let stream = provider.events()
        let collector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in stream { events.append(event) }
            return events
        }

        try await provider.start(sessionID: sessionID, providerEpoch: 7)
        try await provider.append(AudioFrame(samples: [0.1], sampleRate: 16_000, channelCount: 1, startFrame: 0))
        await transport.emit(.connectionChanged(.connected))
        await transport.emit(.partial(text: "今", providerSequence: 1))
        await transport.emit(.partial(text: "今天", providerSequence: 2))
        await transport.emit(.partial(text: "重复不能出现", providerSequence: 2))
        await transport.emit(.failed(code: "network", message: "offline", isRecoverable: true))
        try await waitUntil { await transport.sentFrameCount == 1 }
        try await bounded("provider successful finish") {
            try await provider.finish()
        }
        await provider.cancel()

        let events = try await bounded("provider successful event stream") {
            await collector.value
        }
        precondition(events.contains { if case .connectionChanged(_, .connected) = $0 { true } else { false } })
        precondition(events.contains { if case .partial(_, _, 1, "今") = $0 { true } else { false } })
        precondition(events.contains { if case .partial(_, _, 2, "今天") = $0 { true } else { false } })
        precondition(!events.contains { if case .partial(_, _, _, let text) = $0 { text.contains("不能出现") } else { false } })
        precondition(events.contains { if case .finalized(_, let segment) = $0 { segment.text == "今天" } else { false } })
        precondition(events.contains { if case .failed(_, let failure) = $0 { failure.code == .transportDisconnected && failure.isRecoverable } else { false } })
        precondition(events.filter { if case .completed = $0 { true } else { false } }.count == 1)
        precondition(!events.contains { if case .cancelled = $0 { true } else { false } })
        let finalizedIndex = events.firstIndex { if case .finalized = $0 { true } else { false } }
        let completedIndex = events.firstIndex { if case .completed = $0 { true } else { false } }
        precondition(finalizedIndex != nil && completedIndex != nil && finalizedIndex! < completedIndex!)
        precondition(events.allSatisfy { $0.metadata.sessionID == sessionID && $0.metadata.providerEpoch == 7 })
        let counts = await transport.counts()
        precondition(counts.connect == 1)
        precondition(counts.finish == 1)
        precondition(counts.disconnect == 1)
    }

    private static func successfulFinishCompletesRealSession() async throws {
        let transport = FixtureOnlineStreamingTransport(
            finishBehavior: .completeWithDuplicateAndLateMessages
        )
        let provider = OnlineTranscriptionProvider(id: "online-session-fixture", transport: transport)
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )

        try await session.start()
        try await session.append(AudioFrame(
            samples: [0.1],
            sampleRate: 16_000,
            channelCount: 1,
            startFrame: 0
        ))
        try await bounded("real session finish") {
            await session.finish()
        }

        try await waitUntil { await session.currentState().lifecycle == .completed }
        let state = await session.currentState()
        precondition(state.lifecycle == .completed)
        precondition(state.confirmedText == "今天")
        let counts = await transport.counts()
        precondition(counts.finish == 1)
        precondition(counts.disconnect == 1)
    }

    private static func cancelWinsBeforeServerCompletion() async throws {
        let transport = FixtureOnlineStreamingTransport(
            finishBehavior: .waitForDisconnect
        )
        let provider = OnlineTranscriptionProvider(id: "online-cancel-fixture", transport: transport)
        let stream = provider.events()
        let collector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in stream { events.append(event) }
            return events
        }

        try await provider.start(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 11
        )
        let finishTask = Task { try await provider.finish() }
        try await waitUntil { await transport.finishCount == 1 }
        await provider.cancel()
        try await bounded("cancelled pending finish") {
            try await finishTask.value
        }
        await transport.emit(.completed)

        let events = try await bounded("cancelled provider event stream") {
            await collector.value
        }
        precondition(events.filter { if case .cancelled = $0 { true } else { false } }.count == 1)
        precondition(!events.contains { if case .completed = $0 { true } else { false } })
        let counts = await transport.counts()
        precondition(counts.finish == 1)
        precondition(counts.disconnect == 1)
    }

    private static func bounded<T: Sendable>(
        _ label: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = TimeoutGate(continuation: continuation)
            Task {
                do {
                    gate.resume(with: .success(try await operation()))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(1))
                gate.resume(with: .failure(CheckTimeout(label: label)))
            }
        }
    }

    private static func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("timed out")
    }
}

private struct CheckTimeout: Error {
    let label: String
}

private final class TimeoutGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        let target = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            defer { continuation = nil }
            return continuation
        }
        target?.resume(with: result)
    }
}

private enum FixtureFinishBehavior: Sendable {
    case completeWithDuplicateAndLateMessages
    case waitForDisconnect
}

private actor FixtureOnlineStreamingTransport: OnlineStreamingTransport {
    nonisolated let stream: AsyncStream<OnlineProviderMessage>
    private let continuation: AsyncStream<OnlineProviderMessage>.Continuation
    private(set) var connectCount = 0
    private(set) var sentFrameCount = 0
    private(set) var finishCount = 0
    private(set) var disconnectCount = 0
    private let finishBehavior: FixtureFinishBehavior
    private var finishWaiter: CheckedContinuation<Void, Never>?

    init(finishBehavior: FixtureFinishBehavior) {
        self.finishBehavior = finishBehavior
        var captured: AsyncStream<OnlineProviderMessage>.Continuation!
        stream = AsyncStream { captured = $0 }
        continuation = captured
    }

    func connect(configuration: OnlineProviderConfiguration) async throws { connectCount += 1 }
    func send(_ frame: AudioFrame) async throws { sentFrameCount += 1 }
    func finishInput() async throws {
        finishCount += 1
        switch finishBehavior {
        case .completeWithDuplicateAndLateMessages:
            continuation.yield(.finalized(text: "今天", providerSequence: 3))
            continuation.yield(.completed)
            continuation.yield(.completed)
            continuation.yield(.partial(text: "晚到不能出现", providerSequence: 4))
        case .waitForDisconnect:
            await withCheckedContinuation { finishWaiter = $0 }
        }
    }
    func disconnect() async {
        disconnectCount += 1
        let waiter = finishWaiter
        finishWaiter = nil
        waiter?.resume()
        continuation.finish()
    }
    nonisolated func messages() -> AsyncStream<OnlineProviderMessage> { stream }
    func emit(_ message: OnlineProviderMessage) { continuation.yield(message) }
    func counts() -> (connect: Int, finish: Int, disconnect: Int) {
        (connectCount, finishCount, disconnectCount)
    }
}
