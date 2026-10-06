import Foundation

// Task A2:生产胶囊继续使用中性的 PreviewDisplaySnapshotProjector。
// PreviewDisplaySnapshotProjector 把统一 PreviewViewState 映射为旧胶囊消费的
// PreviewDisplaySnapshot，并施加会话身份锁定、序列单调、终态/失败不喂字纪律。
// 见 docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md Task 2。

@main
struct ProductionPreviewTextProjectionCheck {
    static func main() {
        let sessionA = TranscriptionSessionID(rawValue: UUID())
        let sessionB = TranscriptionSessionID(rawValue: UUID())

        runningStateMapsCharForChar(sessionA)
        staleSequenceIsIgnored(sessionA)
        foreignSessionIsIgnored(primary: sessionA, foreign: sessionB)
        terminalAndFailureAreNotFed(sessionA)
        blankContentIsNotFed(sessionA)

        print("ProductionPreviewTextProjectionCheck passed")
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
        var projection = PreviewDisplaySnapshotProjector()
        let snapshot = projection.apply(state(
            session, sequence: 3, stableCount: 12, stable: "你好世界", volatile: "在说话"
        ))
        precondition(snapshot != nil, "running 且有内容必须产出快照")
        precondition(snapshot?.stableCharacterCount == 12, "稳定字符数必须原样透传")
        precondition(snapshot?.stableWindowText == "你好世界", "稳定窗口文本必须逐字透传")
        precondition(snapshot?.volatileTailText == "在说话", "可变尾部必须逐字透传")
        precondition(snapshot?.displayText == "你好世界在说话", "合成显示文本必须一致")
    }

    private static func staleSequenceIsIgnored(_ session: TranscriptionSessionID) {
        var projection = PreviewDisplaySnapshotProjector()
        _ = projection.apply(state(session, sequence: 5, stableCount: 2, stable: "甲", volatile: "乙"))
        precondition(
            projection.apply(state(session, sequence: 5, stableCount: 2, stable: "甲", volatile: "乙")) == nil,
            "相同序列必须丢弃"
        )
        precondition(
            projection.apply(state(session, sequence: 4, stableCount: 9, stable: "回退", volatile: "了")) == nil,
            "更小序列必须丢弃,防止乱序回退"
        )
        precondition(
            projection.apply(state(session, sequence: 6, stableCount: 3, stable: "前进", volatile: "OK")) != nil,
            "更大序列必须放行"
        )
    }

    private static func foreignSessionIsIgnored(
        primary: TranscriptionSessionID,
        foreign: TranscriptionSessionID
    ) {
        var projection = PreviewDisplaySnapshotProjector()
        _ = projection.apply(state(primary, sequence: 1, stableCount: 1, stable: "锁", volatile: "定"))
        precondition(
            projection.apply(state(foreign, sequence: 99, stableCount: 5, stable: "别的", volatile: "会话")) == nil,
            "锁定首个会话后,异会话事件必须丢弃"
        )
    }

    private static func terminalAndFailureAreNotFed(_ session: TranscriptionSessionID) {
        var projection = PreviewDisplaySnapshotProjector()
        precondition(
            projection.apply(state(
                session, sequence: 2, stableCount: 4, stable: "完了", volatile: "",
                lifecycle: .completed
            )) == nil,
            "终态不喂文字,收尾交回协调器 final 路径"
        )
        precondition(
            projection.apply(state(
                session, sequence: 3, stableCount: 4, stable: "错了", volatile: "",
                failure: TranscriptionFailure(code: .providerUnavailable, message: "x", isRecoverable: true)
            )) == nil,
            "失败态不喂文字"
        )
    }

    private static func blankContentIsNotFed(_ session: TranscriptionSessionID) {
        var projection = PreviewDisplaySnapshotProjector()
        precondition(
            projection.apply(state(session, sequence: 1, stableCount: 0, stable: "", volatile: "   ")) == nil,
            "空白内容不喂字,避免闪现空胶囊"
        )
    }
}
