import Foundation

actor TranscriptionBroadcaster {
    private static let eventCapacity = 64
    private var stateContinuations: [UUID: AsyncStream<TranscriptState>.Continuation] = [:]
    private var eventContinuations: [UUID: AsyncStream<TranscriptionEvent>.Continuation] = [:]
    private var isFinished = false

    func states() -> AsyncStream<TranscriptState> {
        let pair = AsyncStream<TranscriptState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        guard !isFinished else {
            pair.continuation.finish()
            return pair.stream
        }
        let id = UUID()
        stateContinuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStateSubscriber(id) }
        }
        return pair.stream
    }

    func events() -> AsyncStream<TranscriptionEvent> {
        let pair = AsyncStream<TranscriptionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.eventCapacity)
        )
        guard !isFinished else {
            pair.continuation.finish()
            return pair.stream
        }
        let id = UUID()
        eventContinuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventSubscriber(id) }
        }
        return pair.stream
    }

    func publish(state: TranscriptState) {
        guard !isFinished else { return }
        var terminated: [UUID] = []
        for (id, continuation) in stateContinuations {
            if case .terminated = continuation.yield(state) {
                terminated.append(id)
            }
        }
        for id in terminated {
            stateContinuations.removeValue(forKey: id)
        }
    }

    func publish(event: TranscriptionEvent) {
        guard !isFinished else { return }
        var terminated: [UUID] = []
        for (id, continuation) in eventContinuations {
            switch continuation.yield(event) {
            case .enqueued:
                break
            case .dropped:
                continuation.yield(overflowEvent(for: event))
                continuation.finish()
                terminated.append(id)
            case .terminated:
                terminated.append(id)
            @unknown default:
                continuation.finish()
                terminated.append(id)
            }
        }
        for id in terminated {
            eventContinuations.removeValue(forKey: id)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        for continuation in stateContinuations.values {
            continuation.finish()
        }
        for continuation in eventContinuations.values {
            continuation.finish()
        }
        stateContinuations.removeAll(keepingCapacity: false)
        eventContinuations.removeAll(keepingCapacity: false)
    }

    func subscriberCounts() -> (states: Int, events: Int) {
        (stateContinuations.count, eventContinuations.count)
    }

    private func overflowEvent(for event: TranscriptionEvent) -> TranscriptionEvent {
        .failed(
            event.metadata,
            TranscriptionFailure(
                code: .subscriberOverflow,
                message: "Event subscriber exceeded the 64-event buffer.",
                isRecoverable: true
            )
        )
    }

    private func removeStateSubscriber(_ id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func removeEventSubscriber(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }
}
