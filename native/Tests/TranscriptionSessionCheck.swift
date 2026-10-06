import Foundation

@main
struct TranscriptionSessionCheck {
    static func main() async throws {
        try await commandsRemainOrderedAndFinishIsIdempotent()
        try await cancelRejectsLateProviderEvents()
        try await providerSwitchRejectsOldEpochAndPreservesConfirmedText()
        print("TranscriptionSessionCheck passed")
    }

    private static func commandsRemainOrderedAndFinishIsIdempotent() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let provider = FakeTranscriptionProvider(id: "ordered")
        let session = TranscriptionSession(sessionID: sessionID, provider: provider)

        try await session.start()
        try await session.append(frame(startFrame: 0))
        try await session.append(frame(startFrame: 1_600))
        await session.finish()
        await session.finish()

        let commands = await provider.commands
        precondition(commands == ["start:1", "append:0", "append:1600", "finish"])
        let state = await waitForState(session) { $0.lifecycle == .completed }
        precondition(state.lifecycle == .completed)
    }

    private static func cancelRejectsLateProviderEvents() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let provider = FakeTranscriptionProvider(id: "cancel")
        let session = TranscriptionSession(sessionID: sessionID, provider: provider)

        try await session.start()
        await session.cancel()
        await provider.emit(.partial(
            metadata(sessionID, epoch: 1, sequence: 99),
            segmentID: "late",
            revision: 1,
            text: "不能出现"
        ))
        await Task.yield()

        let state = await session.currentState()
        precondition(state.lifecycle == .cancelled)
        precondition(state.volatileText.isEmpty)
        let commands = await provider.commands
        precondition(commands == ["start:1", "cancel"])
    }

    private static func providerSwitchRejectsOldEpochAndPreservesConfirmedText() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let first = FakeTranscriptionProvider(id: "first")
        let second = FakeTranscriptionProvider(id: "second")
        let session = TranscriptionSession(sessionID: sessionID, provider: first)

        try await session.start()
        await first.emit(.finalized(
            metadata(sessionID, epoch: 1, sequence: 1),
            segment: TranscriptSegment(
                id: "confirmed",
                text: "已经确认",
                audioRange: TranscriptionAudioRange(start: 0, end: 1)
            )
        ))
        _ = await waitForState(session) { $0.confirmedText == "已经确认" }

        try await session.switchProvider(to: second)
        await first.emit(.partial(
            metadata(sessionID, epoch: 1, sequence: 2),
            segmentID: "old",
            revision: 1,
            text: "旧 Provider"
        ))
        await second.emit(.partial(
            metadata(sessionID, epoch: 2, sequence: 1),
            segmentID: "new",
            revision: 1,
            text: "新 Provider"
        ))

        let state = await waitForState(session) { $0.volatileText == "新 Provider" }
        precondition(state.providerEpoch == 2)
        precondition(state.confirmedText == "已经确认")
        precondition(state.volatileText == "新 Provider")
        let firstCommands = await first.commands
        let secondCommands = await second.commands
        precondition(firstCommands == ["start:1", "cancel"])
        precondition(secondCommands == ["start:2"])

        await session.cancel()
    }

    private static func waitForState(
        _ session: TranscriptionSession,
        matching predicate: (TranscriptState) -> Bool
    ) async -> TranscriptState {
        for _ in 0..<1_000 {
            let state = await session.currentState()
            if predicate(state) { return state }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for transcription state")
    }

    private static func frame(startFrame: Int64) -> AudioFrame {
        AudioFrame(
            samples: Array(repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            channelCount: 1,
            startFrame: startFrame
        )
    }

    private static func metadata(
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

private actor FakeTranscriptionProvider: TranscriptionProvider {
    nonisolated let id: String
    nonisolated let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )
    private(set) var commands: [String] = []
    private let stream: AsyncStream<TranscriptionEvent>
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private var sessionID: TranscriptionSessionID?
    private var epoch = 0

    init(id: String) {
        self.id = id
        let pair = AsyncStream<TranscriptionEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        self.sessionID = sessionID
        epoch = providerEpoch
        commands.append("start:\(providerEpoch)")
    }

    func append(_ frame: AudioFrame) async throws {
        commands.append("append:\(frame.startFrame)")
    }

    func finish() async throws {
        commands.append("finish")
        guard let sessionID else { return }
        continuation.yield(.completed(metadata(
            sessionID,
            epoch: epoch,
            sequence: 1_000
        )))
    }

    func cancel() async {
        commands.append("cancel")
    }

    nonisolated func events() -> AsyncStream<TranscriptionEvent> {
        stream
    }

    func emit(_ event: TranscriptionEvent) {
        continuation.yield(event)
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
