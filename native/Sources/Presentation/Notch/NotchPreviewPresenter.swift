import AppKit
import QuartzCore

/// 刘海主题的实时预览实现，按是否有物理刘海呈现不同视觉：
///
/// - 无刘海/外接屏：浮在状态栏下方约 5px 的圆角灵动岛，单行 icon | 文字 | pulse，
///   固定宽度，左右图标同尺寸、文字横向居中、整体纵向居中。从中心点放大展开。
/// - 真刘海屏：紧贴刘海下方的紧凑圆角矩形，顶部较大的 icon|刘海|pulse、下方单行文字，
///   圆角与刘海一致。从顶部中心一个小点放大展开。
///
/// 出现/收起都固定面板最终几何，只动画 reveal mask path（无刘海=中心、刘海=顶部中心），
/// 黑色背景、图标、脉冲和文字由同一个 mask 一起裁切展开，避免内容和黑框一前一后。
final class NotchPreviewPresenter: PreviewPresenting {
    var onCycleMode: (() -> Void)?

    // 无刘海灵动岛
    private let barIconSize: CGFloat = 16
    private let edge: CGFloat = 12
    private let textGap: CGFloat = 8
    private let textSlot: CGFloat = 184
    private let pillHeight: CGFloat = 34
    private let pillCorner: CGFloat = 14
    private let belowGap: CGFloat = 5
    // 真刘海岛
    private let notchIconSize: CGFloat = 20
    private let notchPulseSize: CGFloat = 18
    private let notchSideSlot: CGFloat = 34
    private let notchTextRow: CGFloat = 16
    private let notchCorner: CGFloat = 10

    private let panelMargin: CGFloat = 4
    private let openDuration: TimeInterval = 0.3
    private let closeDuration: TimeInterval = 0.22
    private let collapsedScale: CGFloat = 0.01
    private let draftStepInterval: TimeInterval = 0.075

    private let panel: NSPanel
    private let container = NSView()
    private let island = NSView()
    private let backgroundLayer = CAShapeLayer()
    private let revealMaskLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let pulseView = NotchPulseView()
    private let textLabel = NSTextField(labelWithString: "")

    private let textBuffer = CapsuleTextBuffer(animatedTailLimit: 8, firstPreviewMinimumCharacters: 3)
    private var draftTimer: Timer?

    private var currentState = ""
    private var isVisible = false
    private var animationOrigin = CGPoint(x: 0.5, y: 0.5)
    private var screenObserver: NSObjectProtocol?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = container

        island.wantsLayer = true
        island.layer?.backgroundColor = NSColor.clear.cgColor
        island.layer?.masksToBounds = false
        backgroundLayer.fillColor = NSColor.black.cgColor
        island.layer?.addSublayer(backgroundLayer)
        revealMaskLayer.fillColor = NSColor.black.cgColor
        island.layer?.mask = revealMaskLayer
        container.addSubview(island)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        island.addSubview(iconView)
        island.addSubview(pulseView)

        textLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        textLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.95)
        textLabel.alignment = .center
        textLabel.maximumNumberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.drawsBackground = false
        textLabel.isBordered = false
        island.addSubview(textLabel)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.reposition()
            self.applyIslandGeometry()
        }
    }

    deinit {
        draftTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: - PreviewPresenting

    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        iconView.image = appIcon
    }

    func updateTargetApp(appIcon: NSImage?, appName: String?) {
        iconView.image = appIcon
    }

    func updateModeName(_ modeName: String) {}
    func updateAutoTranslateEnabled(_ enabled: Bool) {}
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {}

    func show(state: String, draft: String?) {
        currentState = state
        setDraftTarget(draft ?? "")
        reposition()
        pulseView.startAnimating()
        setVisible(true)
        LaunchDiagnostics.mark("notch_preview_show state=\(state)")
    }

    func updateDraft(_ draft: String) {
        setDraftTarget(draft)
    }

    func hideAnimated() {
        guard isVisible else { return }
        setVisible(false)
        pulseView.stopAnimating()
        draftTimer?.invalidate()
        draftTimer = nil
    }

    func updateBands(_ bands: [Float]) {
        guard let peak = bands.max() else { return }
        pulseView.setLevel(CGFloat(peak))
    }

    func updateInputLevel(db: Float?) {
        guard let db else { return }
        let level = max(0, min(1, (CGFloat(db) + 60) / 60))
        pulseView.setLevel(level)
    }

    // MARK: - Draft typewriter（复用 CapsuleTextBuffer；固定布局）

    private func setDraftTarget(_ draft: String) {
        switch textBuffer.setTarget(draft) {
        case .reset:
            draftTimer?.invalidate()
            draftTimer = nil
            refreshText()
        case .ignored:
            break
        case .updated(_, let needsDraftTimer, let shouldStopDraftTimer):
            refreshText()
            if shouldStopDraftTimer {
                draftTimer?.invalidate()
                draftTimer = nil
            }
            if needsDraftTimer { startDraftTimer() }
        }
    }

    private func startDraftTimer() {
        guard textBuffer.displayedDraft != textBuffer.targetDraft, draftTimer == nil else { return }
        let timer = Timer(timeInterval: draftStepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            switch self.textBuffer.advance() {
            case .finished, .refreshedAndFinished:
                timer.invalidate()
                self.draftTimer = nil
                self.refreshText()
            case .advanced:
                self.refreshText()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        draftTimer = timer
    }

    private func refreshText() {
        textLabel.stringValue = textBuffer.isEmpty ? currentState : textBuffer.displayedDraft
    }

    // MARK: - Geometry & visibility

    private func reposition() {
        guard let geo = NotchGeometry.current() else {
            LaunchDiagnostics.mark("notch_preview_geometry_unavailable")
            return
        }
        let screenFrame = geo.screen.frame
        let topInset = geo.notchRect.height

        let islandW: CGFloat
        let islandH: CGFloat
        var islandTop: CGFloat

        if geo.hasPhysicalNotch {
            let notchW = geo.notchRect.width
            islandW = notchW + 2 * notchSideSlot
            islandH = topInset + notchTextRow + 2
            islandTop = screenFrame.maxY
            island.layer?.cornerRadius = notchCorner
            animationOrigin = CGPoint(x: 0.5, y: 1.0) // 顶部中心

            let topMidY = islandH - topInset / 2
            let leftGap = (islandW - notchW) / 2
            iconView.frame = NSRect(x: (leftGap - notchIconSize) / 2, y: topMidY - notchIconSize / 2, width: notchIconSize, height: notchIconSize)
            pulseView.frame = NSRect(x: islandW - leftGap + (leftGap - notchPulseSize) / 2, y: topMidY - notchPulseSize / 2, width: notchPulseSize, height: notchPulseSize)
            textLabel.frame = NSRect(x: 10, y: 1, width: islandW - 20, height: notchTextRow)
        } else {
            islandW = edge + barIconSize + textGap + textSlot + textGap + barIconSize + edge
            islandH = pillHeight
            islandTop = screenFrame.maxY - topInset - belowGap
            island.layer?.cornerRadius = pillCorner
            animationOrigin = CGPoint(x: 0.5, y: 0.5) // 中心

            let lineH: CGFloat = 18
            iconView.frame = NSRect(x: edge, y: (islandH - barIconSize) / 2, width: barIconSize, height: barIconSize)
            pulseView.frame = NSRect(x: islandW - edge - barIconSize, y: (islandH - barIconSize) / 2, width: barIconSize, height: barIconSize)
            textLabel.frame = NSRect(x: edge + barIconSize + textGap, y: (islandH - lineH) / 2, width: textSlot, height: lineH)
        }

        let panelW = islandW + panelMargin * 2
        let panelH = islandH + panelMargin * 2
        let panelOriginX = min(max(screenFrame.minX, screenFrame.midX - panelW / 2), screenFrame.maxX - panelW)
        let panelOriginY = islandTop - panelMargin - islandH
        withoutLayerActions {
            panel.setFrame(NSRect(x: panelOriginX, y: panelOriginY, width: panelW, height: panelH), display: false)
            island.frame = NSRect(x: panelMargin, y: panelMargin, width: islandW, height: islandH)
            applyIslandGeometry()
        }
        LaunchDiagnostics.mark(
            "notch_preview_layout physical=\(geo.hasPhysicalNotch) w=\(Int(islandW)) h=\(Int(islandH))"
        )
    }

    /// 让 view/layer 始终停在完整最终几何；真实开合只动画黑色背景 path。
    private func applyIslandGeometry() {
        guard let layer = island.layer else { return }
        let f = island.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: f.size)
        layer.position = CGPoint(x: f.midX, y: f.midY)
        backgroundLayer.frame = layer.bounds
        backgroundLayer.path = finalBackgroundPath()
        revealMaskLayer.frame = layer.bounds
        revealMaskLayer.path = finalBackgroundPath()
    }

    private func finalBackgroundPath() -> CGPath {
        let rect = CGRect(origin: .zero, size: island.bounds.size)
        return roundedPath(in: rect)
    }

    private func collapsedBackgroundPath() -> CGPath {
        roundedPath(in: collapsedBackgroundRect())
    }

    private func collapsedBackgroundRect() -> CGRect {
        let bounds = CGRect(origin: .zero, size: island.bounds.size)
        let collapsed = CGSize(
            width: max(1, bounds.width * collapsedScale),
            height: max(1, bounds.height * collapsedScale)
        )
        let originPoint = CGPoint(
            x: bounds.minX + bounds.width * animationOrigin.x,
            y: bounds.minY + bounds.height * animationOrigin.y
        )
        let x = originPoint.x - collapsed.width / 2
        let y: CGFloat
        if animationOrigin.y >= 1 {
            y = originPoint.y - collapsed.height
        } else if animationOrigin.y <= 0 {
            y = originPoint.y
        } else {
            y = originPoint.y - collapsed.height / 2
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: collapsed)
    }

    private func roundedPath(in rect: CGRect) -> CGPath {
        let cornerRadius = island.layer?.cornerRadius ?? pillCorner
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func withoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private func addPathAnimation(
        to layer: CALayer,
        key: String,
        from: CGPath,
        to: CGPath,
        duration: TimeInterval
    ) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func addOpacityAnimation(
        to layer: CALayer,
        key: String,
        from: Float,
        to: Float,
        duration: TimeInterval
    ) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func setVisible(_ visible: Bool) {
        guard let layer = island.layer else { return }
        if visible {
            if isVisible {
                withoutLayerActions {
                    panel.alphaValue = 1
                    applyIslandGeometry()
                    layer.opacity = 1
                }
                return
            }

            isVisible = true
            layer.removeAllAnimations()
            backgroundLayer.removeAllAnimations()
            revealMaskLayer.removeAllAnimations()

            // 先在不可见状态下摆好锚点和收缩起点，避免首次显示时 Core Animation
            // 为 anchor/position/frame 自动补一段从左侧来的隐式动画。
            withoutLayerActions {
                panel.alphaValue = 1
                applyIslandGeometry()
                layer.opacity = 0
                revealMaskLayer.path = collapsedBackgroundPath()
            }

            panel.orderFrontRegardless()

            let startPath = collapsedBackgroundPath()
            let finalPath = finalBackgroundPath()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyIslandGeometry()
            layer.opacity = 1
            revealMaskLayer.path = finalPath
            addPathAnimation(to: revealMaskLayer, key: "openMaskPath", from: startPath, to: finalPath, duration: openDuration)
            addOpacityAnimation(to: layer, key: "fadeIn", from: 0, to: 1, duration: openDuration)
            CATransaction.commit()
        } else {
            isVisible = false
            let currentPath = revealMaskLayer.presentation()?.path ?? revealMaskLayer.path ?? finalBackgroundPath()
            let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
            let endPath = collapsedBackgroundPath()
            layer.removeAllAnimations()
            backgroundLayer.removeAllAnimations()
            revealMaskLayer.removeAllAnimations()

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [panel, layer, backgroundLayer, revealMaskLayer] in
                panel.orderOut(nil)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.removeAllAnimations()
                backgroundLayer.removeAllAnimations()
                revealMaskLayer.removeAllAnimations()
                self.applyIslandGeometry()
                layer.opacity = 1
                CATransaction.commit()
            }
            revealMaskLayer.path = endPath
            layer.opacity = 0
            addPathAnimation(to: revealMaskLayer, key: "closeMaskPath", from: currentPath, to: endPath, duration: closeDuration)
            addOpacityAnimation(to: layer, key: "fadeOut", from: currentOpacity, to: 0, duration: closeDuration)
            CATransaction.commit()
        }
    }
}
