import Foundation

/// 数据层拥有的完整转录快照。它不做可见字符裁剪，也不依赖任何 UI 类型。
struct CompleteTranscriptSnapshot: Equatable, Sendable {
    let revision: Int
    let stableText: String
    let volatileTailText: String
    let lifecycle: TranscriptionLifecycle
    let sourceIdentity: String

    var deliveryText: String {
        TranscriptSnapshotAssembler.deliveryText(
            confirmed: stableText,
            volatile: volatileTailText
        )
    }

    func completing() -> CompleteTranscriptSnapshot {
        CompleteTranscriptSnapshot(
            revision: revision,
            stableText: stableText,
            volatileTailText: volatileTailText,
            lifecycle: .completed,
            sourceIdentity: sourceIdentity
        )
    }
}
