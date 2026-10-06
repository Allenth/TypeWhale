import Foundation

/// 生产胶囊的“文字进料口”抽象。RecordingPanel 已实现 `updateDraft(_:)`,天然满足;
/// 抽出协议只为脱开 AppKit、让投影逻辑可确定性单测。
@MainActor
protocol ProductionPreviewTextSink: AnyObject {
    func updateDraft(_ snapshot: PreviewDisplaySnapshot)
}

/// 让成熟的生产胶囊消费统一 `PreviewViewState`,不再依赖旧 reducer 的直喂路径。
/// 本类只负责文字草稿；`deliversText` 是展示门，只决定当前会话是否把投影后的
/// 文字快照送给胶囊。波形、上下文、录音状态和隐藏生命周期仍由
/// SpeechInputCoordinator 命令式驱动，完整转录与交付缓存不经过本类。
@MainActor
final class ProductionPreviewTextCoordinator {
    /// 每次真正投递给生产胶囊的字符数，供诊断日志使用；跳过（会话/序列/终态过滤）不触发。
    var onDeliveryDiagnostics: ((PreviewViewState, Int) -> Void)?

    private weak var sink: (any ProductionPreviewTextSink)?
    private var projection = PreviewDisplaySnapshotProjector()
    private var subscriptionTask: Task<Void, Never>?

    init(sink: any ProductionPreviewTextSink) {
        self.sink = sink
    }

    func replaceSink(_ sink: any ProductionPreviewTextSink) {
        precondition(subscriptionTask == nil, "Preview sink may change only between sessions")
        self.sink = sink
    }

    deinit {
        subscriptionTask?.cancel()
    }

    func begin(states: AsyncStream<PreviewViewState>, deliversText: Bool) {
        subscriptionTask?.cancel()
        projection.reset()
        subscriptionTask = Task { @MainActor [weak self] in
            for await state in states {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if let snapshot = self.projection.apply(state) {
                    guard deliversText else { continue }
                    guard let sink = self.sink else { continue }
                    sink.updateDraft(snapshot)
                    self.onDeliveryDiagnostics?(state, snapshot.displayText.count)
                }
            }
        }
    }

    func end() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        projection.reset()
    }
}
