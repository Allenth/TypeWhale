import Foundation

final class OnlineTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    let id: String
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )

    private let eventStream: AsyncStream<TranscriptionEvent>
    private let core: OnlineTranscriptionProviderCore

    init(
        id: String,
        transport: any OnlineStreamingTransport,
        configuration: OnlineProviderConfiguration = OnlineProviderConfiguration(
            sampleRate: 16_000,
            channelCount: 1,
            languageHint: "zh",
            connectionTimeoutSeconds: 5
        )
    ) {
        self.id = id
        var captured: AsyncStream<TranscriptionEvent>.Continuation!
        eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        core = OnlineTranscriptionProviderCore(
            transport: transport,
            configuration: configuration,
            continuation: captured
        )
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        try await core.start(sessionID: sessionID, providerEpoch: providerEpoch)
    }

    func append(_ frame: AudioFrame) async throws { try await core.append(frame) }
    func finish() async throws { try await core.finish() }
    func cancel() async { await core.cancel() }
    func events() -> AsyncStream<TranscriptionEvent> { eventStream }
}

private actor OnlineTranscriptionProviderCore {
    private let transport: any OnlineStreamingTransport
    private let configuration: OnlineProviderConfiguration
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private var sessionID: TranscriptionSessionID?
    private var providerEpoch = 0
    private var sequence: UInt64 = 0
    private var partialRevision = 0
    private var finalizedIndex = 0
    private var lastProviderSequence: UInt64 = 0
    private var sampleRate = 0
    private var audioEndFrame: Int64 = 0
    private var terminal = false
    private var terminalSettled = false
    private var messageTask: Task<Void, Never>?
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        transport: any OnlineStreamingTransport,
        configuration: OnlineProviderConfiguration,
        continuation: AsyncStream<TranscriptionEvent>.Continuation
    ) {
        self.transport = transport
        self.configuration = configuration
        self.continuation = continuation
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        guard self.sessionID == nil, !terminal else { throw TranscriptionSessionError.terminal }
        self.sessionID = sessionID
        self.providerEpoch = providerEpoch
        try await transport.connect(configuration: configuration)
        let messages = transport.messages()
        messageTask = Task { [weak self] in
            for await message in messages {
                guard !Task.isCancelled else { return }
                await self?.consume(message)
            }
        }
    }

    func append(_ frame: AudioFrame) async throws {
        guard sessionID != nil else { throw TranscriptionSessionError.notStarted }
        guard !terminal else { throw TranscriptionSessionError.terminal }
        try await transport.send(frame)
        sampleRate = frame.sampleRate
        audioEndFrame = max(audioEndFrame, frame.startFrame + Int64(frame.samples.count))
    }

    func finish() async throws {
        guard sessionID != nil else { throw TranscriptionSessionError.notStarted }
        if terminal {
            await waitForTerminalSettlement()
            return
        }
        try await transport.finishInput()
        await waitForTerminalSettlement()
    }

    private func waitForTerminalSettlement() async {
        guard !terminalSettled else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append(continuation)
        }
    }

    func cancel() async {
        guard !terminal, sessionID != nil else { return }
        terminal = true
        messageTask?.cancel()
        messageTask = nil
        await transport.disconnect()
        continuation.yield(.cancelled(metadata()))
        continuation.finish()
        terminalSettled = true
        resumeCompletionWaiters()
    }

    private func consume(_ message: OnlineProviderMessage) async {
        guard !terminal, sessionID != nil else { return }
        switch message {
        case .partial(let text, let providerSequence):
            guard accept(providerSequence) else { return }
            partialRevision += 1
            continuation.yield(.partial(
                metadata(),
                segmentID: "online-tail",
                revision: partialRevision,
                text: text
            ))
        case .finalized(let text, let providerSequence):
            guard accept(providerSequence) else { return }
            finalizedIndex += 1
            continuation.yield(.finalized(
                metadata(),
                segment: TranscriptSegment(
                    id: "online-final-\(finalizedIndex)",
                    text: text,
                    audioRange: TranscriptionAudioRange(
                        start: 0,
                        end: Double(audioEndFrame) / Double(max(1, sampleRate))
                    )
                )
            ))
        case .completed:
            terminal = true
            await transport.disconnect()
            messageTask = nil
            continuation.yield(.completed(metadata()))
            continuation.finish()
            terminalSettled = true
            resumeCompletionWaiters()
        case .connectionChanged(let state):
            continuation.yield(.connectionChanged(metadata(), state))
        case .failed(_, let message, let isRecoverable):
            continuation.yield(.failed(
                metadata(),
                TranscriptionFailure(
                    code: .transportDisconnected,
                    message: message,
                    isRecoverable: isRecoverable
                )
            ))
        }
    }

    private func resumeCompletionWaiters() {
        let waiters = completionWaiters
        completionWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    private func accept(_ providerSequence: UInt64) -> Bool {
        guard providerSequence > lastProviderSequence else { return false }
        lastProviderSequence = providerSequence
        return true
    }

    private func metadata() -> TranscriptionEventMetadata {
        sequence += 1
        return TranscriptionEventMetadata(
            sessionID: sessionID!,
            providerEpoch: providerEpoch,
            sequence: sequence,
            emittedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }
}
