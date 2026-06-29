import AppKit
import QuartzCore

final class RecordingPanel: NSPanel {
    private let visualBackground = NSVisualEffectView()
    private let capsule = RecordingCapsuleView()
    private let infoBar = NSStackView()
    private let appIconView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let dotLabel = NSTextField(labelWithString: "·")
    private let modeButton = NSButton()
    private let translationDotLabel = NSTextField(labelWithString: "·")
    private let translationBadge = NSTextField(labelWithString: "自动翻译")
    private let statusDotLabel = NSTextField(labelWithString: "·")
    private let statusBadge = NSTextField(labelWithString: "")
    private let levelDotLabel = NSTextField(labelWithString: "·")
    private let levelLabel = NSTextField(labelWithString: "")
    private let infoBarHeight: CGFloat = 22
    private var hasContext = false
    private let fadeDuration: TimeInterval = 0.25
    private let resizeDuration: TimeInterval = 0.18
    private var visibilityGeneration = 0

    /// 点击胶囊上的模式标签时回调，用于手动切换整理模式。
    var onCycleMode: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 164, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        visualBackground.frame = NSRect(x: 0, y: 0, width: 164, height: 44)
        visualBackground.autoresizingMask = [.width, .height]
        visualBackground.material = .hudWindow
        visualBackground.blendingMode = .behindWindow
        visualBackground.state = .active
        visualBackground.appearance = NSAppearance(named: .vibrantDark)
        visualBackground.wantsLayer = true
        visualBackground.layer?.cornerRadius = 21
        visualBackground.layer?.masksToBounds = true

        capsule.frame = visualBackground.bounds
        capsule.autoresizingMask = [.width, .height]
        visualBackground.addSubview(capsule)

        configureInfoBar()
        contentView = visualBackground
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func configureInfoBar() {
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        appIconView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        appNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        appNameLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.82)
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        appNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        dotLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.5)

        modeButton.isBordered = false
        modeButton.setButtonType(.momentaryChange)
        modeButton.target = self
        modeButton.action = #selector(modeTapped)
        modeButton.toolTip = "点击切换整理模式"
        setModeTitle("自动")

        translationDotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        translationDotLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.5)
        translationDotLabel.isHidden = true

        translationBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        translationBadge.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.36, alpha: 0.98)
        translationBadge.lineBreakMode = .byTruncatingTail
        translationBadge.maximumNumberOfLines = 1
        translationBadge.toolTip = "自动翻译已开启"
        translationBadge.isHidden = true

        statusDotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusDotLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.5)
        statusDotLabel.isHidden = true

        statusBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        statusBadge.textColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        statusBadge.lineBreakMode = .byTruncatingTail
        statusBadge.maximumNumberOfLines = 1
        statusBadge.isHidden = true

        levelDotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        levelDotLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.5)
        levelDotLabel.isHidden = true

        // 实时输入电平（dBFS），等宽数字 + 固定宽度避免数值变化时胶囊抖动；用于肉眼分辨近场/远场强弱。
        levelLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        levelLabel.textColor = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.80, alpha: 0.98)
        levelLabel.maximumNumberOfLines = 1
        levelLabel.alignment = .right
        levelLabel.toolTip = "实时输入电平（dBFS），越接近 0 越响"
        levelLabel.isHidden = true
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        infoBar.orientation = .horizontal
        infoBar.alignment = .centerY
        infoBar.spacing = 5
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.setViews(
            [appIconView, appNameLabel, dotLabel, modeButton, translationDotLabel, translationBadge, statusDotLabel, statusBadge, levelDotLabel, levelLabel],
            in: .leading
        )
        infoBar.isHidden = true
        visualBackground.addSubview(infoBar)

        NSLayoutConstraint.activate([
            infoBar.topAnchor.constraint(equalTo: visualBackground.topAnchor, constant: 6),
            infoBar.centerXAnchor.constraint(equalTo: visualBackground.centerXAnchor),
            infoBar.leadingAnchor.constraint(greaterThanOrEqualTo: visualBackground.leadingAnchor, constant: 14),
            infoBar.trailingAnchor.constraint(lessThanOrEqualTo: visualBackground.trailingAnchor, constant: -14),
        ])
    }

    private func setModeTitle(_ text: String) {
        modeButton.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
        ])
    }

    @objc private func modeTapped() {
        onCycleMode?()
    }

    /// 设置胶囊顶部的「App 图标 · 模式」信息条。
    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        updateTargetApp(appIcon: appIcon, appName: appName, shouldResize: false)
        setModeTitle(modeName)
        setTranslationBadgeVisible(autoTranslateEnabled)
        hasContext = true
        infoBar.isHidden = false
        capsule.contextTopInset = infoBarHeight
        resizeAndPosition()
    }

    /// 当前焦点应用变化时，更新胶囊顶部的 App 图标与名称。
    func updateTargetApp(appIcon: NSImage?, appName: String?) {
        updateTargetApp(appIcon: appIcon, appName: appName, shouldResize: true)
    }

    /// 仅更新模式标签（手动切换后调用），不改动 App 信息。
    func updateModeName(_ modeName: String) {
        setModeTitle(modeName)
        if hasContext { resizeAndPosition() }
    }

    func updateAutoTranslateEnabled(_ enabled: Bool) {
        setTranslationBadgeVisible(enabled)
        if hasContext { resizeAndPosition() }
    }

    /// 录音倒计时与内存状态：用整圈边框颜色 + 顶部小字提示当前状态。
    /// remainingSeconds 为 nil 表示非录音；memoryHigh 表示内存达到预警档位。
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {
        var badgeText: String?
        var badgeColor = NSColor(calibratedWhite: 1, alpha: 0.78)
        var borderColor: NSColor?

        if let remainingSeconds {
            badgeText = String(format: "剩 %d:%02d", remainingSeconds / 60, remainingSeconds % 60)
            if remainingSeconds <= 10 {
                borderColor = .systemRed
            } else if remainingSeconds <= 30 {
                borderColor = .systemOrange
            } else {
                borderColor = nil
            }
        }
        if memoryHigh {
            badgeText = badgeText.map { "\($0) · 内存偏高" } ?? "内存偏高"
            badgeColor = .systemRed
            borderColor = .systemRed
        }

        let hasStatus = (badgeText != nil)
        statusBadge.stringValue = badgeText ?? ""
        statusBadge.textColor = badgeColor
        statusBadge.isHidden = !(hasStatus && hasContext)
        statusDotLabel.isHidden = !(hasStatus && hasContext)
        capsule.statusBorderColor = hasStatus ? borderColor : nil
        if hasContext { resizeAndPosition() }
    }

    private func updateTargetApp(appIcon: NSImage?, appName: String?, shouldResize: Bool) {
        let rawName = (appName?.isEmpty == false) ? appName! : "未知应用"
        appNameLabel.stringValue = String(rawName.prefix(16))
        appIconView.image = appIcon
        appIconView.isHidden = (appIcon == nil)
        if shouldResize, hasContext { resizeAndPosition() }
    }

    private func setTranslationBadgeVisible(_ visible: Bool) {
        translationDotLabel.isHidden = !visible
        translationBadge.isHidden = !visible
    }

    func show(state: String, draft: String? = nil) {
        visibilityGeneration += 1
        let shouldFadeIn = !isVisible
        // 新一帧胶囊先清掉上一次的电平读数，避免显示陈旧数值。录音中会被实时更新重新点亮。
        levelLabel.isHidden = true
        levelDotLabel.isHidden = true
        capsule.update(state: state, draft: draft)
        resizeAndPosition()
        if shouldFadeIn {
            alphaValue = 0
        }
        orderFrontRegardless()
        if shouldFadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    func updateDraft(_ draft: String) {
        capsule.update(draft: draft)
        resizeAndPosition()
    }

    func hideAnimated() {
        guard isVisible else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, generation == self.visibilityGeneration else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }

    private func resizeAndPosition() {
        let bodySize = capsule.preferredSize
        var width = bodySize.width
        if hasContext {
            infoBar.layoutSubtreeIfNeeded()
            width = max(width, min(320, ceil(infoBar.fittingSize.width) + 30))
        }
        let size = NSSize(width: width, height: bodySize.height)
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let anchorCenter = NSPoint(x: frame.midX, y: frame.minY + 68)
        let targetFrame = NSRect(
            x: anchorCenter.x - size.width / 2,
            y: anchorCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        guard isVisible else {
            setFrame(targetFrame, display: true)
            return
        }
        if abs(self.frame.width - targetFrame.width) < 0.5,
           abs(self.frame.height - targetFrame.height) < 0.5,
           abs(self.frame.origin.x - targetFrame.origin.x) < 0.5,
           abs(self.frame.origin.y - targetFrame.origin.y) < 0.5 {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(targetFrame, display: true)
        }
    }

    func updateBands(_ bands: [Float]) {
        capsule.update(bands: bands)
    }

    /// 更新胶囊上的实时输入电平读数（dBFS）；db 为 nil 表示清除（非录音时）。
    /// 固定宽度标签，仅在显隐切换时才重新布局，数值变化不触发胶囊抖动。
    func updateInputLevel(db: Float?) {
        guard hasContext else { return }
        if let db {
            let shown = max(-80, min(0, Int(db.rounded())))
            levelLabel.stringValue = "\(shown) dB"
            let wasHidden = levelLabel.isHidden
            levelLabel.isHidden = false
            levelDotLabel.isHidden = false
            if wasHidden { resizeAndPosition() }
        } else {
            let wasShown = !levelLabel.isHidden
            levelLabel.isHidden = true
            levelDotLabel.isHidden = true
            if wasShown { resizeAndPosition() }
        }
    }
}
