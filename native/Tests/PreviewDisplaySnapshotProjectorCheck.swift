import Foundation

@main
struct PreviewDisplaySnapshotProjectorCheck {
    static func main() {
        let sessionA = TranscriptionSessionID(rawValue: UUID())
        let sessionB = TranscriptionSessionID(rawValue: UUID())

        runningStateMapsCharForChar(sessionA)
        staleSequenceIsIgnored(sessionA)
        foreignSessionIsIgnored(primary: sessionA, foreign: sessionB)
        terminalAndFailureAreNotFed(sessionA)
        blankContentIsNotFed(sessionA)
        resetAllowsNewSession(sessionA, sessionB)

        print("PreviewDisplaySnapshotProjectorCheck passed")
    }

    private static func state(
        _ sessionID: TranscriptionSessionID,
        sequence: UInt64,
        stableCount: Int,
        stable: String,
        volatile: String,
        lifecycle: TranscriptionLifecycle = .running,
        failure: TranscriptionFailure? = nil
    ) -> PreviewViewState {
        PreviewViewState(
            sessionID: sessionID,
            providerEpoch: 1,
            sequence: sequence,
            stableCharacterCount: stableCount,
            stableWindowText: stable,
            volatileTailText: volatile,
            lifecycle: lifecycle,
            failure: failure
        )
    }

    private static func runningStateMapsCharForChar(_ session: TranscriptionSessionID) {
        var projector = PreviewDisplaySnapshotProjector()
        let snapshot = projector.apply(state(
            session, sequence: 3, stableCount: 12, stable: "你好世界", volatile: "在说话"
        ))
        precondition(snapshot != nil)
        precondition(snapshot?.revision == 3)
        precondition(snapshot?.stableCharacterCount == 12)
        precondition(snapshot?.stableWindowText == "你好世界")
        precondition(snapshot?.volatileTailText == "在说话")
        precondition(snapshot?.displayText == "你好世界在说话")
    }

    private static func staleSequenceIsIgnored(_ session: TranscriptionSessionID) {
        var projector = PreviewDisplaySnapshotProjector()
        _ = projector.apply(state(session, sequence: 5, stableCount: 2, stable: "甲", volatile: "乙"))
        precondition(projector.apply(state(session, sequence: 5, stableCount: 2, stable: "甲", volatile: "乙")) == nil)
        precondition(projector.apply(state(session, sequence: 4, stableCount: 9, stable: "回退", volatile: "了")) == nil)
        precondition(projector.apply(state(session, sequence: 6, stableCount: 3, stable: "前进", volatile: "OK")) != nil)
    }

    private static func foreignSessionIsIgnored(
        primary: TranscriptionSessionID,
        foreign: TranscriptionSessionID
    ) {
        var projector = PreviewDisplaySnapshotProjector()
        _ = projector.apply(state(primary, sequence: 1, stableCount: 1, stable: "锁", volatile: "定"))
        precondition(projector.apply(state(foreign, sequence: 99, stableCount: 5, stable: "别的", volatile: "会话")) == nil)
    }

    private static func terminalAndFailureAreNotFed(_ session: TranscriptionSessionID) {
        var projector = PreviewDisplaySnapshotProjector()
        precondition(projector.apply(state(
            session, sequence: 2, stableCount: 4, stable: "完了", volatile: "",
            lifecycle: .completed
        )) == nil)
        precondition(projector.apply(state(
            session, sequence: 3, stableCount: 4, stable: "错了", volatile: "",
            failure: TranscriptionFailure(code: .providerUnavailable, message: "x", isRecoverable: true)
        )) == nil)
    }

    private static func blankContentIsNotFed(_ session: TranscriptionSessionID) {
        var projector = PreviewDisplaySnapshotProjector()
        precondition(projector.apply(state(session, sequence: 1, stableCount: 0, stable: "", volatile: "   ")) == nil)
    }

    private static func resetAllowsNewSession(
        _ oldSession: TranscriptionSessionID,
        _ newSession: TranscriptionSessionID
    ) {
        var projector = PreviewDisplaySnapshotProjector()
        _ = projector.apply(state(oldSession, sequence: 1, stableCount: 1, stable: "旧", volatile: ""))
        projector.reset()
        let snapshot = projector.apply(state(newSession, sequence: 1, stableCount: 1, stable: "新", volatile: ""))
        precondition(snapshot?.displayText == "新")
    }
}
