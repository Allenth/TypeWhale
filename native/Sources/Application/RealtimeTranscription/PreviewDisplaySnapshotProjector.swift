import Foundation

/// 纯投影：把统一 `PreviewViewState` 映射为旧胶囊消费的 `PreviewDisplaySnapshot`。
///
/// 这不是生产胶囊专属逻辑，而是数据层到展示快照的统一投影：
/// - 会话身份锁定：锁住首个 `sessionID`，晚到的异会话事件一律丢弃。
/// - 序列单调：`sequence` 不大于上次的一律丢弃，防止乱序回退。
/// - 终态/失败/空白不喂字：只在 `.running` 且有实义内容时产出快照。
struct PreviewDisplaySnapshotProjector: Sendable {
    private var expectedSessionID: TranscriptionSessionID?
    private var lastSequence: UInt64?

    mutating func apply(_ state: PreviewViewState) -> PreviewDisplaySnapshot? {
        if expectedSessionID == nil { expectedSessionID = state.sessionID }
        guard state.sessionID == expectedSessionID else { return nil }

        if let lastSequence, state.sequence <= lastSequence { return nil }
        lastSequence = state.sequence

        guard state.failure == nil, state.lifecycle == .running else { return nil }
        guard !state.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return PreviewDisplaySnapshot(
            revision: Int(truncatingIfNeeded: state.sequence),
            stableCharacterCount: state.stableCharacterCount,
            stableWindowText: state.stableWindowText,
            volatileTailText: state.volatileTailText
        )
    }

    mutating func reset() {
        expectedSessionID = nil
        lastSequence = nil
    }
}
