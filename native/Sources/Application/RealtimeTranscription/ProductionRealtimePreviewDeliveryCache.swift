import Foundation

/// 生产链路的实时预览最终交付缓存。
///
/// 只由 SpeechInputCoordinator 的生产预览 snapshot 写入；
/// 不属于 ShadowPreview / CandidatePreview runtime，也不读取任何胶囊 View。
struct ProductionRealtimePreviewDeliveryCache: Sendable {
    private var snapshot: CompleteTranscriptSnapshot?
    private var audioCoverageSeconds: TimeInterval?
    private var recordingDurationSeconds: TimeInterval?
    private var completionObserver: (@Sendable (CompleteTranscriptSnapshot) -> Void)?

    /// 末尾未覆盖容忍度：实时快照约 0.5s 一次；超过这个缺口说明停止前尾巴没有进入缓存。
    private static let tailCoverageToleranceSeconds: TimeInterval = 0.35

    mutating func reset(
        completionObserver: (@Sendable (CompleteTranscriptSnapshot) -> Void)? = nil
    ) {
        snapshot = nil
        audioCoverageSeconds = nil
        recordingDurationSeconds = nil
        self.completionObserver = completionObserver
    }

    mutating func consume(
        _ snapshot: CompleteTranscriptSnapshot,
        audioCoverageSeconds: TimeInterval? = nil
    ) {
        self.snapshot = snapshot
        self.audioCoverageSeconds = audioCoverageSeconds
        recordingDurationSeconds = nil
    }

    mutating func complete(recordingDurationSeconds: TimeInterval? = nil) {
        guard snapshot != nil else { return }
        self.recordingDurationSeconds = recordingDurationSeconds
        snapshot = snapshot?.completing()
        if let snapshot {
            completionObserver?(snapshot)
        }
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
