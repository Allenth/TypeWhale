import Foundation

/// 实时预览链路的最终可交付缓存。
///
/// 这个缓存只承载数据层产出的完整稳定文本和当前尾巴；不接受 UI 展示快照，
/// 不读取任何胶囊 View，也不决定最终粘贴策略。
struct RealtimePreviewDeliveryCache: Sendable {
    private var snapshot: CompleteTranscriptSnapshot?

    mutating func consume(_ snapshot: CompleteTranscriptSnapshot) {
        self.snapshot = snapshot
    }

    mutating func complete() {
        snapshot = snapshot?.completing()
    }

    func deliverySnapshot() -> CandidateDeliverySnapshot? {
        guard let snapshot else { return nil }
        return CandidateDeliverySnapshot(
            text: snapshot.deliveryText,
            source: .realtimePreviewDeliveryCache,
            lifecycle: snapshot.lifecycle
        )
    }
}
