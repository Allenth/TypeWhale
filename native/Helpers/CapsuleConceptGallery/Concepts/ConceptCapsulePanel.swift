import AppKit

/// 概念胶囊承载面板：把任意一套概念视图（墨滴/雾线/玉弧）包装成一个悬浮窗，
/// 并实现完整的 `PreviewPresenting`——因此它跟生产胶囊消费**同一份数据源调用**，
/// 是「订阅数据源」的真实载体。定位由 MultiCapsulePreviewPresenter 统一排布，保证不遮盖。
final class ConceptCapsulePanel: NSPanel, PreviewPresenting {
    let capsule: CapsuleConcept

    // 上下文缓存：更新单项（换 App / 换模式）时合并回 conceptSetContext。
    private var cachedIcon: NSImage?
    private var cachedApp = ""
    private var cachedMode = "自动"
    private var cachedAuto = false
    private var currentAccent: ConceptAccent = .normal
    private var currentClaw: ConceptClawStatus = .checking
    private var visibilityGeneration = 0

    var onCycleMode: (() -> Void)?
    var presentationFrame: CGRect? { isVisible ? frame : nil }

    /// 当前偏好尺寸（供排布器计算相邻位置）。
    var preferredSize: NSSize { capsule.conceptPreferredSize }

    private final class ClickView: NSView {
        var onClick: (() -> Void)?
        override var isFlipped: Bool { false }
        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    init(view: CapsuleConcept) {
        capsule = view
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        let root = ClickView(frame: NSRect(x: 0, y: 0, width: 200, height: 72))
        root.autoresizingMask = [.width, .height]
        root.onClick = { [weak self] in self?.onCycleMode?() }
        view.frame = root.bounds
        view.autoresizingMask = [.width, .height]
        root.addSubview(view)
        contentView = root
        sizeToContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func sizeToContent() {
        setContentSize(capsule.conceptPreferredSize)
    }

    /// 供排布器调用：定位到指定原点，并按内容尺寸调整大小。
    func place(at origin: CGPoint) {
        let size = capsule.conceptPreferredSize
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func mergeContext() {
        capsule.conceptSetContext(appIcon: cachedIcon, appName: cachedApp, modeName: cachedMode, autoTranslate: cachedAuto)
    }

    private func pushAccent() {
        capsule.conceptUpdate(accent: currentAccent, claw: currentClaw)
    }

    // MARK: PreviewPresenting

    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        cachedIcon = appIcon; cachedApp = appName ?? ""; cachedMode = modeName; cachedAuto = autoTranslateEnabled
        mergeContext()
    }
    func updateTargetApp(appIcon: NSImage?, appName: String?) {
        cachedIcon = appIcon; cachedApp = appName ?? ""
        mergeContext()
    }
    func updateModeName(_ modeName: String) { cachedMode = modeName; mergeContext() }
    func updateModeEmphasis(_ emphasis: PreviewModeEmphasis) { /* 概念视图暂不区分自动解析强调 */ }
    func updateAutoTranslateEnabled(_ enabled: Bool) { cachedAuto = enabled; mergeContext() }
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {
        capsule.conceptUpdate(remainingSeconds: remainingSeconds, memoryHigh: memoryHigh)
    }
    func updateOllamaHealth(isHealthy: Bool) { capsule.conceptUpdate(ollamaHealthy: isHealthy) }
    func updateAccent(_ accent: PreviewAccent) {
        switch accent {
        case .normal: currentAccent = .normal
        case .ideaPill: currentAccent = .ideaPill
        case .openClaw: currentAccent = .openClaw
        }
        pushAccent()
    }
    func updateOpenClawConnectionStatus(_ status: OpenClawConnectionStatus) {
        switch status {
        case .checking: currentClaw = .checking
        case .connected: currentClaw = .connected
        case .unavailable: currentClaw = .unavailable
        }
        pushAccent()
    }
    func show(state: String, draft: String?) {
        visibilityGeneration += 1
        alphaValue = 1
        capsule.conceptUpdate(state: state)
        let visibleDraft = draft ?? ""
        capsule.conceptUpdate(draft: visibleDraft, stableCount: visibleDraft.count)
        orderFrontRegardless()
    }
    func updateDraft(_ draft: String) { capsule.conceptUpdate(draft: draft, stableCount: draft.count) }
    func updateDraft(_ snapshot: PreviewDisplaySnapshot) { capsule.conceptUpdate(snapshot: snapshot) }
    func hideAnimated() {
        guard isVisible else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        currentAccent = .normal; currentClaw = .checking
        capsule.conceptUpdate(accent: .normal, claw: .checking)
        capsule.conceptUpdate(ollamaHealthy: false)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            orderOut(nil)
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.visibilityGeneration == generation else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }
    func updateBands(_ bands: [Float]) { capsule.conceptUpdate(bands: bands) }
    func updateInputLevel(db: Float?) { _ = db }
}
