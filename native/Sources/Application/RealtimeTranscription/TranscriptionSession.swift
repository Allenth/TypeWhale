import Foundation

actor TranscriptionSession {
    private let sessionID: TranscriptionSessionID
    private var providerEpoch = 1
    private var provider: any TranscriptionProvider
    private var reducer: TranscriptReducer
    private var providerEventTask: Task<Void, Never>?
    private let broadcaster = TranscriptionBroadcaster()
    private var started = false
    private var finishRequested = false

    init(
        sessionID: TranscriptionSessionID,
        provider: any TranscriptionProvider
    ) {
        self.sessionID = sessionID
        self.provider = provider
        reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)
    }

    func start() async throws {
        guard !started else { return }
        guard !reducer.state.lifecycle.isTerminal else {
            throw TranscriptionSessionError.terminal
        }
        let eventStream = provider.events()
        startConsuming(eventStream)
        do {
            try await provider.start(
                sessionID: sessionID,
                providerEpoch: providerEpoch
            )
            started = true
            await publishState(reducer.state)
        } catch {
            providerEventTask?.cancel()
            providerEventTask = nil
            throw error
        }
    }

    func append(_ frame: AudioFrame) async throws {
        guard started else { throw TranscriptionSessionError.notStarted }
        guard !finishRequested, !reducer.state.lifecycle.isTerminal else {
            throw TranscriptionSessionError.terminal
        }
        try await provider.append(frame)
    }

    func finish() async {
        guard started,
              !finishRequested,
              !reducer.state.lifecycle.isTerminal else { return }
        finishRequested = true
        do {
            try await provider.finish()
        } catch {
            await applySyntheticFailure(error)
        }
    }

    func cancel() async {
        guard !reducer.state.lifecycle.isTerminal else { return }
        finishRequested = true
        if started {
            await provider.cancel()
        }
        let event = TranscriptionEvent.cancelled(syntheticMetadata())
        if let state = reducer.apply(event) {
            await publish(event: event, state: state)
        }
        providerEventTask?.cancel()
        providerEventTask = nil
        await broadcaster.finish()
    }

    func switchProvider(
        to replacement: any TranscriptionProvider
    ) async throws {
        guard started else { throw TranscriptionSessionError.notStarted }
        guard !finishRequested, !reducer.state.lifecycle.isTerminal else {
            throw TranscriptionSessionError.terminal
        }

        providerEventTask?.cancel()
        providerEventTask = nil
        await provider.cancel()

        providerEpoch += 1
        provider = replacement
        reducer = TranscriptReducer(
            migrating: reducer.state,
            toProviderEpoch: providerEpoch
        )
        let eventStream = replacement.events()
        startConsuming(eventStream)
        do {
            try await replacement.start(
                sessionID: sessionID,
                providerEpoch: providerEpoch
            )
            await publishState(reducer.state)
        } catch {
            providerEventTask?.cancel()
            providerEventTask = nil
            throw error
        }
    }

    func currentState() -> TranscriptState {
        reducer.state
    }

    func states() async -> AsyncStream<TranscriptState> {
        let stream = await broadcaster.states()
        await broadcaster.publish(state: reducer.state)
        return stream
    }

    func events() async -> AsyncStream<TranscriptionEvent> {
        await broadcaster.events()
    }

    private func startConsuming(_ stream: AsyncStream<TranscriptionEvent>) {
        providerEventTask?.cancel()
        providerEventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(event)
            }
        }
    }

    private func receive(_ event: TranscriptionEvent) async {
        guard let state = reducer.apply(event) else { return }
        await publish(event: event, state: state)
        if state.lifecycle.isTerminal {
            finishRequested = true
            await broadcaster.finish()
        }
    }

    private func applySyntheticFailure(_ error: Error) async {
        let failure = TranscriptionFailure(
            code: .providerUnavailable,
            message: String(describing: error),
            isRecoverable: false
        )
        let event = TranscriptionEvent.failed(syntheticMetadata(), failure)
        if let state = reducer.apply(event) {
            await publish(event: event, state: state)
            await broadcaster.finish()
        }
    }

    private func syntheticMetadata() -> TranscriptionEventMetadata {
        TranscriptionEventMetadata(
            sessionID: sessionID,
            providerEpoch: providerEpoch,
            sequence: reducer.state.lastSequence + 1,
            emittedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func publish(event: TranscriptionEvent, state: TranscriptState) async {
        await broadcaster.publish(event: event)
        await publishState(state)
    }

    private func publishState(_ state: TranscriptState) async {
        await broadcaster.publish(state: state)
    }
}
