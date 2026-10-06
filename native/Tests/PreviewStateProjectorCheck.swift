import Foundation

@main
struct PreviewStateProjectorCheck {
    static func main() {
        tailReceivesVisibleCapacityBeforeStableText()
        longTailRemainsBoundedWithoutChangingStableCount()
        identityLifecycleAndFailureArePreserved()
        stableBoundaryIsMonotonicAcrossProjections()
        print("PreviewStateProjectorCheck passed")
    }

    private static func tailReceivesVisibleCapacityBeforeStableText() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 4)
        let confirmed = String(repeating: "稳", count: 200)
        let tail = String(repeating: "新", count: 40)
        _ = reducer.apply(.finalized(
            metadata(sessionID, epoch: 4, sequence: 1),
            segment: segment("stable", text: confirmed)
        ))
        guard let state = reducer.apply(.partial(
            metadata(sessionID, epoch: 4, sequence: 2),
            segmentID: "tail",
            revision: 1,
            text: tail
        )) else {
            preconditionFailure("partial state missing")
        }

        let viewState = PreviewStateProjector.project(state, visibleCharacterLimit: 160)
        precondition(viewState.sessionID == sessionID)
        precondition(viewState.providerEpoch == 4)
        precondition(viewState.sequence == 2)
        precondition(viewState.stableCharacterCount == 200)
        precondition(viewState.volatileTailText == tail)
        precondition(viewState.stableWindowText.count == 120)
        precondition(viewState.displayText.count == 160)
    }

    private static func longTailRemainsBoundedWithoutChangingStableCount() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)
        _ = reducer.apply(.finalized(
            metadata(sessionID, epoch: 1, sequence: 1),
            segment: segment("stable", text: String(repeating: "稳", count: 30))
        ))
        guard let state = reducer.apply(.partial(
            metadata(sessionID, epoch: 1, sequence: 2),
            segmentID: "tail",
            revision: 1,
            text: String(repeating: "尾", count: 80)
        )) else {
            preconditionFailure("partial state missing")
        }

        let viewState = PreviewStateProjector.project(state, visibleCharacterLimit: 20)
        precondition(viewState.stableCharacterCount == 30)
        precondition(viewState.stableWindowText.isEmpty)
        precondition(viewState.volatileTailText == String(repeating: "尾", count: 20))
        precondition(viewState.displayText.count == 20)
    }

    private static func identityLifecycleAndFailureArePreserved() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 9)
        let failure = TranscriptionFailure(
            code: .transportDisconnected,
            message: "offline",
            isRecoverable: false
        )
        guard let state = reducer.apply(.failed(
            metadata(sessionID, epoch: 9, sequence: 7),
            failure
        )) else {
            preconditionFailure("failure state missing")
        }

        let viewState = PreviewStateProjector.project(state, visibleCharacterLimit: 160)
        precondition(viewState.sessionID == sessionID)
        precondition(viewState.providerEpoch == 9)
        precondition(viewState.sequence == 7)
        precondition(viewState.lifecycle == .failed)
        precondition(viewState.failure == failure)
    }

    private static func stableBoundaryIsMonotonicAcrossProjections() {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 1)
        guard let first = reducer.apply(.finalized(
            metadata(sessionID, epoch: 1, sequence: 1),
            segment: segment("first", text: "第一段")
        )) else {
            preconditionFailure("first final state missing")
        }
        guard let second = reducer.apply(.finalized(
            metadata(sessionID, epoch: 1, sequence: 2),
            segment: segment("second", text: "第二段确认")
        )) else {
            preconditionFailure("second final state missing")
        }

        let firstView = PreviewStateProjector.project(first, visibleCharacterLimit: 6)
        let secondView = PreviewStateProjector.project(second, visibleCharacterLimit: 6)
        precondition(secondView.stableCharacterCount > firstView.stableCharacterCount)
        precondition(secondView.stableWindowText == "段第二段确认")
        precondition(secondView.sequence > firstView.sequence)
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

    private static func segment(_ id: String, text: String) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            audioRange: TranscriptionAudioRange(start: 0, end: 1)
        )
    }
}
