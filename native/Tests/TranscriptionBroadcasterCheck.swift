import Foundation

@main
struct TranscriptionBroadcasterCheck {
    static func main() async {
        await stateSubscribersIndependentlyReceiveOnlyNewestState()
        await slowEventSubscriberOverflowsWithoutAffectingFastSubscriber()
        await finishTerminatesEverySubscriberExactlyOnce()
        print("TranscriptionBroadcasterCheck passed")
    }

    private static func stateSubscribersIndependentlyReceiveOnlyNewestState() async {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let broadcaster = TranscriptionBroadcaster()
        let firstStream = await broadcaster.states()
        let secondStream = await broadcaster.states()
        var first = firstStream.makeAsyncIterator()
        var second = secondStream.makeAsyncIterator()

        for sequence in 1...3 {
            await broadcaster.publish(state: state(
                sessionID: sessionID,
                sequence: UInt64(sequence),
                text: "state-\(sequence)"
            ))
        }

        let firstNewest = await first.next()
        let secondNewest = await second.next()
        precondition(firstNewest?.lastSequence == 3)
        precondition(firstNewest?.volatileText == "state-3")
        precondition(secondNewest == firstNewest)
    }

    private static func slowEventSubscriberOverflowsWithoutAffectingFastSubscriber() async {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let broadcaster = TranscriptionBroadcaster()
        let fastStream = await broadcaster.events()
        let slowStream = await broadcaster.events()
        var fast = fastStream.makeAsyncIterator()
        var slow = slowStream.makeAsyncIterator()

        for sequence in 1...65 {
            let event = partialEvent(sessionID: sessionID, sequence: UInt64(sequence))
            await broadcaster.publish(event: event)
            let fastEvent = await fast.next()
            precondition(fastEvent?.metadata.sequence == UInt64(sequence))
        }

        var slowEvents: [TranscriptionEvent] = []
        while let event = await slow.next() {
            slowEvents.append(event)
        }
        guard case .failed(let metadata, let failure) = slowEvents.last else {
            preconditionFailure("slow subscriber must terminate with overflow failure")
        }
        precondition(metadata.sequence == 65)
        precondition(failure.code == .subscriberOverflow)
        precondition(failure.isRecoverable)
        precondition(slowEvents.count == 64)

        await broadcaster.publish(event: partialEvent(sessionID: sessionID, sequence: 66))
        let stillActive = await fast.next()
        precondition(stillActive?.metadata.sequence == 66)
    }

    private static func finishTerminatesEverySubscriberExactlyOnce() async {
        let broadcaster = TranscriptionBroadcaster()
        let stateStream = await broadcaster.states()
        let eventStream = await broadcaster.events()
        var states = stateStream.makeAsyncIterator()
        var events = eventStream.makeAsyncIterator()

        await broadcaster.finish()
        await broadcaster.finish()

        let finalState = await states.next()
        let finalEvent = await events.next()
        precondition(finalState == nil)
        precondition(finalEvent == nil)
        let counts = await broadcaster.subscriberCounts()
        precondition(counts.states == 0)
        precondition(counts.events == 0)
    }

    private static func state(
        sessionID: TranscriptionSessionID,
        sequence: UInt64,
        text: String
    ) -> TranscriptState {
        TranscriptState(
            sessionID: sessionID,
            providerEpoch: 1,
            lastSequence: sequence,
            confirmedSegments: [],
            volatileSegmentID: "segment",
            volatileRevision: Int(sequence),
            volatileText: text,
            lifecycle: .running,
            failure: nil,
            connectionState: .connected
        )
    }

    private static func partialEvent(
        sessionID: TranscriptionSessionID,
        sequence: UInt64
    ) -> TranscriptionEvent {
        .partial(
            TranscriptionEventMetadata(
                sessionID: sessionID,
                providerEpoch: 1,
                sequence: sequence,
                emittedAtUptime: TimeInterval(sequence)
            ),
            segmentID: "segment",
            revision: Int(sequence),
            text: "text-\(sequence)"
        )
    }
}
