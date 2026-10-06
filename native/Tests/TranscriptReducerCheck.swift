import Foundation

@main
struct TranscriptReducerCheck {
    static func main() {
        partialRevisionsReplaceOnlyTheMutableTail()
        reconciledSnapshotPublishesConfirmedAndVolatileAtomically()
        finalizedSegmentsAreImmutableAndIdempotent()
        staleIdentityAndSequenceAreRejected()
        terminalEventsRejectLaterMutation()
        recoverableFailuresRemainNonTerminal()
        print("TranscriptReducerCheck passed")
    }

    private static func reconciledSnapshotPublishesConfirmedAndVolatileAtomically() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)
        let confirmed = segment("confirmed-1", text: "今天讨论", start: 0, end: 2)

        let state = reducer.apply(.reconciled(
            metadata(sessionID, epoch: 1, sequence: 1),
            finalizedSegments: [confirmed],
            volatileSegmentID: "sensevoice-tail",
            revision: 1,
            text: "在线模型"
        ))

        precondition(state?.lastSequence == 1)
        precondition(state?.confirmedSegments == [confirmed])
        precondition(state?.confirmedText == "今天讨论")
        precondition(state?.volatileText == "在线模型")
        precondition(state?.failure == nil)
    }

    private static func partialRevisionsReplaceOnlyTheMutableTail() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)

        let first = reducer.apply(.partial(
            metadata(sessionID, epoch: 1, sequence: 1),
            segmentID: "segment-0",
            revision: 1,
            text: "今天"
        ))
        precondition(first?.volatileText == "今天")
        precondition(first?.volatileRevision == 1)

        let revised = reducer.apply(.partial(
            metadata(sessionID, epoch: 1, sequence: 2),
            segmentID: "segment-0",
            revision: 2,
            text: "今天讨论"
        ))
        precondition(revised?.volatileText == "今天讨论")
        precondition(revised?.confirmedText.isEmpty == true)

        let olderRevision = reducer.apply(.partial(
            metadata(sessionID, epoch: 1, sequence: 3),
            segmentID: "segment-0",
            revision: 1,
            text: "旧修订"
        ))
        precondition(olderRevision == nil)
        precondition(reducer.state.volatileText == "今天讨论")
        precondition(reducer.state.lastSequence == 2)
    }

    private static func finalizedSegmentsAreImmutableAndIdempotent() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 3)
        _ = reducer.apply(.partial(
            metadata(sessionID, epoch: 3, sequence: 1),
            segmentID: "segment-0",
            revision: 1,
            text: "今天讨论"
        ))

        let finalSegment = segment("segment-0", text: "今天讨论", start: 0, end: 2)
        let finalized = reducer.apply(.finalized(
            metadata(sessionID, epoch: 3, sequence: 2),
            segment: finalSegment
        ))
        precondition(finalized?.confirmedSegments == [finalSegment])
        precondition(finalized?.confirmedText == "今天讨论")
        precondition(finalized?.volatileText.isEmpty == true)

        let duplicate = reducer.apply(.finalized(
            metadata(sessionID, epoch: 3, sequence: 3),
            segment: finalSegment
        ))
        precondition(duplicate == nil)
        precondition(reducer.state.confirmedSegments == [finalSegment])

        let rewriteFinalized = reducer.apply(.partial(
            metadata(sessionID, epoch: 3, sequence: 4),
            segmentID: "segment-0",
            revision: 2,
            text: "不允许改写"
        ))
        precondition(rewriteFinalized == nil)
        precondition(reducer.state.confirmedText == "今天讨论")
    }

    private static func staleIdentityAndSequenceAreRejected() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 7)
        _ = reducer.apply(.partial(
            metadata(sessionID, epoch: 7, sequence: 10),
            segmentID: "segment-0",
            revision: 1,
            text: "当前"
        ))

        let wrongSession = reducer.apply(.partial(
            metadata(TranscriptionSessionID(rawValue: UUID()), epoch: 7, sequence: 11),
            segmentID: "segment-0",
            revision: 2,
            text: "其他会话"
        ))
        let wrongEpoch = reducer.apply(.partial(
            metadata(sessionID, epoch: 6, sequence: 11),
            segmentID: "segment-0",
            revision: 2,
            text: "旧 Provider"
        ))
        let duplicateSequence = reducer.apply(.partial(
            metadata(sessionID, epoch: 7, sequence: 10),
            segmentID: "segment-0",
            revision: 2,
            text: "重复顺序"
        ))

        precondition(wrongSession == nil)
        precondition(wrongEpoch == nil)
        precondition(duplicateSequence == nil)
        precondition(reducer.state.volatileText == "当前")
    }

    private static func terminalEventsRejectLaterMutation() {
        let completedID = TranscriptionSessionID(rawValue: UUID())
        var completed = TranscriptReducer(sessionID: completedID, providerEpoch: 1)
        let completedState = completed.apply(.completed(metadata(completedID, epoch: 1, sequence: 1)))
        precondition(completedState?.lifecycle == .completed)
        precondition(completed.apply(.partial(
            metadata(completedID, epoch: 1, sequence: 2),
            segmentID: "late",
            revision: 1,
            text: "晚到"
        )) == nil)

        let cancelledID = TranscriptionSessionID(rawValue: UUID())
        var cancelled = TranscriptReducer(sessionID: cancelledID, providerEpoch: 1)
        let cancelledState = cancelled.apply(.cancelled(metadata(cancelledID, epoch: 1, sequence: 1)))
        precondition(cancelledState?.lifecycle == .cancelled)
        precondition(cancelled.apply(.finalized(
            metadata(cancelledID, epoch: 1, sequence: 2),
            segment: segment("late", text: "晚到", start: 0, end: 1)
        )) == nil)
    }

    private static func recoverableFailuresRemainNonTerminal() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)
        let failure = TranscriptionFailure(
            code: .providerUnavailable,
            message: "temporary outage",
            isRecoverable: true
        )
        let failedState = reducer.apply(.failed(
            metadata(sessionID, epoch: 1, sequence: 1),
            failure
        ))
        precondition(failedState?.lifecycle == .running)
        precondition(failedState?.failure == failure)

        let recovered = reducer.apply(.partial(
            metadata(sessionID, epoch: 1, sequence: 2),
            segmentID: "segment-1",
            revision: 1,
            text: "恢复"
        ))
        precondition(recovered?.volatileText == "恢复")
        precondition(recovered?.failure == nil)
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

    private static func segment(
        _ id: String,
        text: String,
        start: TimeInterval,
        end: TimeInterval
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            audioRange: TranscriptionAudioRange(start: start, end: end)
        )
    }
}
