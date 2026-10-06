import AppKit

/// 多胶囊分发器：实现 `PreviewPresenting`，把协调器的**每一个数据源调用**同时转发给
/// 「原胶囊（anchor）+ 三套概念胶囊」，并把三套向上堆叠在原胶囊之上、彼此不遮盖。
///
/// 正式接入只需一行——把 SpeechInputCoordinator 里
/// `private var popup: PreviewPresenting = RecordingPanel()`
/// 换成 `MultiCapsulePreviewPresenter.standard()`；本类不改动任何既有代码。
final class MultiCapsulePreviewPresenter: PreviewPresenting {
    /// 原胶囊（生产 RecordingPanel）：既是数据转发目标，也是堆叠布局的锚点。可为 nil（纯概念对比场景）。
    private let anchor: PreviewPresenting?
    /// 三套概念胶囊面板。
    private let variants: [ConceptCapsulePanel]
    private let stackGap: CGFloat = 10

    var onCycleMode: (() -> Void)? {
        didSet {
            anchor?.onCycleMode = onCycleMode
            variants.forEach { panel in panel.onCycleMode = { [weak self] in self?.onCycleMode?() } }
        }
    }
    var presentationFrame: CGRect? { anchor?.presentationFrame }

    init(anchor: PreviewPresenting?, variants: [ConceptCapsulePanel]) {
        self.anchor = anchor
        self.variants = variants
    }

    /// 仅用概念胶囊装配（无原胶囊锚点），供独立预览 / 无生产依赖场景。
    static func conceptsOnly() -> MultiCapsulePreviewPresenter {
        MultiCapsulePreviewPresenter(anchor: nil, variants: [
            ConceptCapsulePanel(view: InkwellCapsuleView()),
            ConceptCapsulePanel(view: MistlineCapsuleView()),
            ConceptCapsulePanel(view: JadeArcCapsuleView()),
        ])
    }

    private var all: [PreviewPresenting] { ([anchor].compactMap { $0 }) + variants }

    // MARK: 布局——三套向上堆叠在锚点之上，居中对齐，越界则钳制到可见区。

    private func relayout() {
        guard let fallbackScreen = NSScreen.main else { return }
        let fallbackFrame = fallbackScreen.visibleFrame
        let base = anchor?.presentationFrame ?? CGRect(
            x: fallbackFrame.midX - 90,
            y: fallbackFrame.minY + 40,
            width: 180,
            height: 44
        )
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(base) }) ?? fallbackScreen
        let vis = screen.visibleFrame
        let sizes = variants.map(\.preferredSize)
        let totalHeight = sizes.reduce(0) { $0 + $1.height } + stackGap * CGFloat(max(0, sizes.count - 1))
        let preferredY = base.maxY + stackGap
        var y = min(preferredY, vis.maxY - 12 - totalHeight)
        y = max(vis.minY + 12, y)
        for (panel, size) in zip(variants, sizes) {
            var x = base.midX - size.width / 2
            x = max(vis.minX + 12, min(x, vis.maxX - 12 - size.width))
            panel.place(at: CGPoint(x: x, y: y))
            y += size.height + stackGap
        }
    }

    // MARK: PreviewPresenting——逐项 fan-out 后重排。

    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        all.forEach { $0.setContext(appIcon: appIcon, appName: appName, modeName: modeName, autoTranslateEnabled: autoTranslateEnabled) }
        relayout()
    }
    func updateTargetApp(appIcon: NSImage?, appName: String?) {
        all.forEach { $0.updateTargetApp(appIcon: appIcon, appName: appName) }
        relayout()
    }
    func updateModeName(_ modeName: String) { all.forEach { $0.updateModeName(modeName) }; relayout() }
    func updateModeEmphasis(_ emphasis: PreviewModeEmphasis) { all.forEach { $0.updateModeEmphasis(emphasis) } }
    func updateAutoTranslateEnabled(_ enabled: Bool) { all.forEach { $0.updateAutoTranslateEnabled(enabled) }; relayout() }
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {
        all.forEach { $0.updateRecordingStatus(remainingSeconds: remainingSeconds, memoryHigh: memoryHigh) }
        relayout()
    }
    func updateOllamaHealth(isHealthy: Bool) { all.forEach { $0.updateOllamaHealth(isHealthy: isHealthy) } }
    func updateAccent(_ accent: PreviewAccent) { all.forEach { $0.updateAccent(accent) } }
    func updateOpenClawConnectionStatus(_ status: OpenClawConnectionStatus) {
        all.forEach { $0.updateOpenClawConnectionStatus(status) }
    }
    func show(state: String, draft: String?) {
        relayout()
        all.forEach { $0.show(state: state, draft: draft) }
        relayout()
    }
    func updateDraft(_ draft: String) { all.forEach { $0.updateDraft(draft) }; relayout() }
    func updateDraft(_ snapshot: PreviewDisplaySnapshot) { all.forEach { $0.updateDraft(snapshot) }; relayout() }
    func hideAnimated() { all.forEach { $0.hideAnimated() } }
    func updateBands(_ bands: [Float]) { all.forEach { $0.updateBands(bands) } }
    func updateInputLevel(db: Float?) { all.forEach { $0.updateInputLevel(db: db) } }
}
