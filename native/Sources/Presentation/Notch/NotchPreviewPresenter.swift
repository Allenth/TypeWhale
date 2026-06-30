import AppKit
import QuartzCore

/// 刘海主题的实时预览实现，按是否有物理刘海呈现不同视觉：
///
/// - 无刘海/外接屏：浮在状态栏下方约 5px 的圆角灵动岛，单行 icon | 文字 | pulse，
///   固定宽度，左右图标同尺寸、文字横向居中、整体纵向居中。从中心点放大展开。
/// - 真刘海屏：紧贴刘海下方的紧凑圆角矩形，顶部较大的 icon|刘海|pulse、下方单行文字，
///   圆角与刘海一致。从顶部中心一个小点放大展开。
///
/// 出现/收起都以各自锚点做「单点」缩放（无刘海=中心、刘海=顶部中心）+ 淡入淡出。
/// 锚点在 orderFront 之后、不可见时设定，避免首次从左向右展开与闪动。
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
    private let closeDuration: TimeInterval = 0.2
    private let draftStepInterval: TimeInterval = 0.075

    private let panel: NSPanel
    private let container = NSView()
    private let island = NSView()
    private let iconView = NSImageView()
    private let pulseView = NotchPulseView()
    private let textLabel = NSTextField(labelWithString: "")

    private let textBuffer = CapsuleTextBuffer(animatedTailLimit: 8, firstPreviewMinimumCharacters: 3)
    private var draftTimer: Timer?

    private var currentState = ""
    private var isVisible = false
    private var islandAnchor = CGPoint(x: 0.5, y: 0.5)
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
        island.layer?.backgroundColor = NSColor.black.cgColor
        island.layer?.masksToBounds = true
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
            self.applyIslandAnchor()
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
            islandAnchor = CGPoint(x: 0.5, y: 1.0) // 顶部中心

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
            islandAnchor = CGPoint(x: 0.5, y: 0.5) // 中心

            let lineH: CGFloat = 18
            iconView.frame = NSRect(x: edge, y: (islandH - barIconSize) / 2, width: barIconSize, height: barIconSize)
            pulseView.frame = NSRect(x: islandW - edge - barIconSize, y: (islandH - barIconSize) / 2, width: barIconSize, height: barIconSize)
            textLabel.frame = NSRect(x: edge + barIconSize + textGap, y: (islandH - lineH) / 2, width: textSlot, height: lineH)
        }

        let panelW = islandW + panelMargin * 2
        let panelH = islandH + panelMargin * 2
        let panelOriginX = min(max(screenFrame.minX, screenFrame.midX - panelW / 2), screenFrame.maxX - panelW)
        let panelOriginY = islandTop - panelMargin - islandH
        panel.setFrame(NSRect(x: panelOriginX, y: panelOriginY, width: panelW, height: panelH), display: false)
        island.frame = NSRect(x: panelMargin, y: panelMargin, width: islandW, height: islandH)
        LaunchDiagnostics.mark(
            "notch_preview_layout physical=\(geo.hasPhysicalNotch) w=\(Int(islandW)) h=\(Int(islandH))"
        )
    }

    /// 显式锁定缩放锚点（无刘海=中心、刘海=顶部中心），并校正 position 保持位置不动。
    private func applyIslandAnchor() {
        guard let layer = island.layer else { return }
        let f = island.frame
        layer.anchorPoint = islandAnchor
        layer.position = CGPoint(x: f.minX + f.width * islandAnchor.x, y: f.minY + f.height * islandAnchor.y)
    }

    private func setVisible(_ visible: Bool) {
        guard let layer = island.layer else { return }
        if visible {
            isVisible = true
            panel.alphaValue = 1
            layer.opacity = 0 // 不可见，规避锚点设定与首帧的闪动
            panel.orderFrontRegardless()
            applyIslandAnchor() // orderFront 之后再设锚点，首次也从正确的点展开
            layer.removeAllAnimations()
            CATransaction.begin()
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            let open = CABasicAnimation(keyPath: "transform.scale")
            open.fromValue = 0.01
            open.toValue = 1.0
            open.duration = openDuration
            open.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(open, forKey: "open")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = min(openDuration, 0.18)
            layer.add(fade, forKey: "fadeIn")
            CATransaction.commit()
        } else {
            isVisible = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { [panel, layer] in
                panel.orderOut(nil)
                layer.removeAllAnimations()
                layer.transform = CATransform3DIdentity
                layer.opacity = 1
            }
            // 终态保持「单点收拢 + 透明」直到 orderOut，避免回弹/闪动。
            layer.transform = CATransform3DMakeScale(0.01, 0.01, 1)
            layer.opacity = 0
            let close = CABasicAnimation(keyPath: "transform.scale")
            close.fromValue = 1.0
            close.toValue = 0.01
            close.duration = closeDuration
            close.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(close, forKey: "close")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = closeDuration
            layer.add(fade, forKey: "fadeOut")
            CATransaction.commit()
        }
    }
}
