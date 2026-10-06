import AppKit
import QuartzCore

final class RecordingPanel: NSPanel, PreviewPresenting {
    var presentationFrame: CGRect? { frame }
    private let panelShell = MainCapsulePanelShell()
    private let contentRoot = NSView()
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
    private let infoBarHeight: CGFloat = 22
    private var hasContext = false
    private let fadeDuration: TimeInterval = 0.25
    private let resizeDuration: TimeInterval = 0.18
    private var visibilityGeneration = 0
    private var currentStatusBorderColor: NSColor?
    private var accent: PreviewAccent = .normal
    private var modeTitleText = "自动"
    private var modeEmphasis: PreviewModeEmphasis = .normal
    private var modeButtonWidthConstraint: NSLayoutConstraint?
    private var contextState = MainCapsuleContext.empty

    /// 点击胶囊上的模式标签时回调，用于手动切换整理模式。
    var onCycleMode: (() -> Void)?

    init() {
        let initialFrame = NSRect(origin: .zero, size: MainCapsulePanelShell.initialContentSize)
        super.init(
            contentRect: initialFrame,
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

        contentRoot.frame = initialFrame
        contentRoot.autoresizingMask = [.width, .height]
        contentRoot.wantsLayer = true
        contentRoot.layer?.backgroundColor = NSColor.clear.cgColor

        visualBackground.frame = initialFrame
        visualBackground.autoresizingMask = []
        visualBackground.material = .hudWindow
        visualBackground.blendingMode = .behindWindow
        visualBackground.state = .active
        visualBackground.appearance = NSAppearance(named: .vibrantDark)
        visualBackground.wantsLayer = true
        visualBackground.layer?.cornerRadius = UITheme.capsuleCornerRadius
        visualBackground.layer?.masksToBounds = true
        contentRoot.addSubview(visualBackground)

        capsule.frame = contentRoot.bounds
        capsule.autoresizingMask = []
        contentRoot.addSubview(capsule)

        configureInfoBar()

        contentView = contentRoot
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func configureInfoBar() {
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        appIconView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        appNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        appNameLabel.textColor = UITheme.waterInkMuted
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        appNameLabel.cell?.wraps = false
        appNameLabel.cell?.isScrollable = true
        appNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        dotLabel.textColor = UITheme.waterInkFaint

        modeButton.isBordered = false
        modeButton.setButtonType(.momentaryChange)
        modeButton.target = self
        modeButton.action = #selector(modeTapped)
        modeButton.toolTip = "点击切换整理模式"
        modeButton.lineBreakMode = .byTruncatingTail
        modeButton.cell?.wraps = false
        modeButton.cell?.isScrollable = true
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        setModeTitle("自动")

        translationDotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        translationDotLabel.textColor = UITheme.waterInkFaint
        translationDotLabel.isHidden = true

        translationBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        translationBadge.textColor = UITheme.waterInkWarning.withAlphaComponent(0.98)
        translationBadge.lineBreakMode = .byTruncatingTail
        translationBadge.maximumNumberOfLines = 1
        translationBadge.cell?.wraps = false
        translationBadge.cell?.isScrollable = true
        translationBadge.toolTip = "自动翻译已开启"
        translationBadge.isHidden = true

        statusDotLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusDotLabel.textColor = UITheme.waterInkFaint
        statusDotLabel.isHidden = true

        statusBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        statusBadge.textColor = UITheme.waterInkText
        statusBadge.lineBreakMode = .byTruncatingTail
        statusBadge.maximumNumberOfLines = 1
        statusBadge.cell?.wraps = false
        statusBadge.cell?.isScrollable = true
        statusBadge.isHidden = true

        [
            appNameLabel,
            dotLabel,
            translationDotLabel,
            translationBadge,
            statusDotLabel,
            statusBadge,
        ].forEach(configureSingleLineLabel)

        infoBar.orientation = .horizontal
        infoBar.alignment = .centerY
        infoBar.spacing = 5
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.distribution = .gravityAreas
        infoBar.setViews(
            [appIconView, appNameLabel, dotLabel, modeButton, translationDotLabel, translationBadge, statusDotLabel, statusBadge],
            in: .leading
        )
        infoBar.isHidden = true
        contentRoot.addSubview(infoBar)

        NSLayoutConstraint.activate([
            infoBar.topAnchor.constraint(equalTo: visualBackground.topAnchor, constant: 6),
            infoBar.centerXAnchor.constraint(equalTo: visualBackground.centerXAnchor),
            infoBar.leadingAnchor.constraint(greaterThanOrEqualTo: visualBackground.leadingAnchor, constant: 14),
            infoBar.trailingAnchor.constraint(lessThanOrEqualTo: visualBackground.trailingAnchor, constant: -14),
        ])
    }

    private func configureSingleLineLabel(_ label: NSTextField) {
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = false
        label.cell?.isScrollable = true
    }

    private func setModeTitle(_ text: String) {
        modeTitleText = text
        refreshModeTitle()
    }

    private func refreshModeTitle() {
        let color: NSColor
        switch modeEmphasis {
        case .normal:
            color = UITheme.waterInkText
        case .automaticResolved:
            color = UITheme.waterInkWarning.withAlphaComponent(0.98)
        }
        modeButton.attributedTitle = NSAttributedString(string: modeTitleText, attributes: [
            .font: modeTitleFont(for: modeTitleText),
            .foregroundColor: color,
        ])
        updateModeButtonWidth()
    }

    private func updateModeButtonWidth() {
        let requiredWidth = ceil(modeButton.attributedTitle.size().width) + 8
        if let modeButtonWidthConstraint {
            modeButtonWidthConstraint.constant = requiredWidth
        } else {
            let constraint = modeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: requiredWidth)
            constraint.priority = .required
            constraint.isActive = true
            modeButtonWidthConstraint = constraint
        }
    }

    private func modeTitleFont(for text: String) -> NSFont {
        switch text.count {
        case 0...6:
            return .systemFont(ofSize: 11, weight: .semibold)
        case 7...9:
            return .systemFont(ofSize: 10, weight: .semibold)
        default:
            return .systemFont(ofSize: 9, weight: .semibold)
        }
    }

    @objc private func modeTapped() {
        onCycleMode?()
    }

    /// 设置胶囊顶部的「App 图标 · 模式」信息条。
    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        contextState = MainCapsuleContext(
            targetAppName: appName,
            modeName: modeName,
            autoTranslateEnabled: autoTranslateEnabled
        )
        applyContextPresentation(appIcon: appIcon)
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
        contextState.modeName = modeName
        let presentation = MainCapsuleContextPresentation(
            context: contextState,
            hasAppIcon: !appIconView.isHidden
        )
        setModeTitle(presentation.modeNameText)
        if hasContext { resizeAndPosition() }
    }

    func updateModeEmphasis(_ emphasis: PreviewModeEmphasis) {
        modeEmphasis = emphasis
        refreshModeTitle()
    }

    func updateAutoTranslateEnabled(_ enabled: Bool) {
        contextState.autoTranslateEnabled = enabled
        let presentation = MainCapsuleContextPresentation(
            context: contextState,
            hasAppIcon: !appIconView.isHidden
        )
        setTranslationBadgeVisible(!presentation.translationBadgeHidden)
        if hasContext { resizeAndPosition() }
    }

    /// 录音倒计时与内存状态：用整圈边框颜色 + 顶部小字提示当前状态。
    /// remainingSeconds 为 nil 表示非录音；memoryHigh 表示内存达到预警档位。
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {
        var badgeText: String?
        var badgeColor = UITheme.waterInkMuted
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
        currentStatusBorderColor = hasStatus ? borderColor : nil
        applyBorderState()
        if hasContext { resizeAndPosition() }
    }

    func updateOpenClawConnectionStatus(_ status: OpenClawConnectionStatus) {
        capsule.openClawConnectionStatus = status
    }

    func updateAccent(_ accent: PreviewAccent) {
        self.accent = accent
        applyBorderState()
    }

    private func applyBorderState() {
        let accentBorderColor: NSColor?
        switch accent {
        case .normal:
            accentBorderColor = nil
            capsule.innerGlow = .none
        case .ideaPill:
            accentBorderColor = RecordingCapsuleView.ideaPillBorderColor
            capsule.innerGlow = .ideaPill
        case .openClaw:
            accentBorderColor = RecordingCapsuleView.openClawBorderColor
            capsule.innerGlow = .openClaw
        }
        capsule.statusBorderColor = currentStatusBorderColor ?? accentBorderColor
        capsule.defaultBorderHidden = accentBorderColor != nil
    }

    private func updateTargetApp(appIcon: NSImage?, appName: String?, shouldResize: Bool) {
        contextState.targetAppName = appName
        applyContextPresentation(appIcon: appIcon, updateMode: false, updateTranslation: false)
        if shouldResize, hasContext { resizeAndPosition() }
    }

    private func applyContextPresentation(
        appIcon: NSImage?,
        updateMode: Bool = true,
        updateTranslation: Bool = true
    ) {
        let presentation = MainCapsuleContextPresentation(
            context: contextState,
            hasAppIcon: appIcon != nil
        )
        appNameLabel.stringValue = presentation.appNameText
        appIconView.image = appIcon
        appIconView.isHidden = presentation.appIconHidden
        if updateMode {
            setModeTitle(presentation.modeNameText)
        }
        if updateTranslation {
            setTranslationBadgeVisible(!presentation.translationBadgeHidden)
        }
    }

    private func setTranslationBadgeVisible(_ visible: Bool) {
        translationDotLabel.isHidden = !visible
        translationBadge.isHidden = !visible
    }

    func show(state: String, draft: String? = nil) {
        visibilityGeneration += 1
        let shouldFadeIn = !isVisible
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
        LaunchDiagnostics.mark(
            "capsule_show_result theme=classic visible=\(isVisible) alpha=\(String(format: "%.2f", alphaValue)) fade_in=\(shouldFadeIn) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))"
        )
    }

    func updateDraft(_ draft: String) {
        capsule.update(draft: draft)
        resizeAndPosition()
    }

    func updateDraft(_ snapshot: PreviewDisplaySnapshot) {
        capsule.update(snapshot: snapshot)
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
            // OpenClaw 的外置徽章会扩大窗口；淡出期间必须保留原强调态，
            // 否则普通边框会在旧尺寸上重画，短暂露出一圈灰色外框。
            self.updateAccent(.normal)
            self.updateOpenClawConnectionStatus(.checking)
        }
    }

    private func resizeAndPosition() {
        let bodySize = capsule.preferredSize
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let materialFrame = capsule.materialFrame(for: bodySize)
        let rightOverhang = max(0, bodySize.width - materialFrame.width)
        let requiredTopInfoBarWidth: CGFloat?
        if hasContext {
            infoBar.layoutSubtreeIfNeeded()
            requiredTopInfoBarWidth = requiredWidthForTopInfoBar()
        } else {
            requiredTopInfoBarWidth = nil
        }
        let size = panelShell.panelSize(
            bodySize: bodySize,
            requiredTopInfoBarWidth: requiredTopInfoBarWidth,
            minimumBodyWidth: RecordingCapsuleView.minimumBodyWidth,
            rightOverhang: rightOverhang,
            screenVisibleFrame: frame
        )
        layoutContentSubviews(for: size)
        let targetFrame = panelShell.targetFrame(panelSize: size, screenVisibleFrame: frame)
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

    private func requiredWidthForTopInfoBar() -> CGFloat {
        ceil(infoBar.fittingSize.width)
    }

    private func layoutContentSubviews(for size: NSSize) {
        let frames = panelShell.layoutFrames(
            panelSize: size,
            materialFrame: capsule.materialFrame(for: size)
        )
        contentRoot.frame = frames.contentRoot
        capsule.frame = frames.capsule
        visualBackground.frame = frames.visualBackground
    }

    /// 主题选择页使用的静态快照：直接渲染当前生产胶囊，不创建第二套视觉。
    /// 只设置演示状态并离屏缓存，不显示窗口、不启动录音、不写入设置。
    func makeThemePreviewSnapshot(
        accent: PreviewAccent,
        modeName: String,
        state: String = "录音中"
    ) -> NSImage? {
        let appIcon = NSImage(
            systemSymbolName: "message.fill",
            accessibilityDescription: "目标应用"
        )
        setContext(
            appIcon: appIcon,
            appName: "ChatGPT",
            modeName: modeName,
            autoTranslateEnabled: false
        )
        updateAccent(accent)
        updateOpenClawConnectionStatus(accent == .openClaw ? .connected : .checking)
        updateRecordingStatus(remainingSeconds: 118, memoryHigh: false)
        capsule.update(
            state: state,
            bands: [0.18, 0.48, 0.26, 0.72, 0.32, 0.58, 0.22]
        )
        resizeAndPosition()
        contentRoot.layoutSubtreeIfNeeded()
        contentRoot.displayIfNeeded()
        return contentRoot.typeWhaleSnapshotImage()
    }

    func updateBands(_ bands: [Float]) {
        capsule.update(bands: bands)
    }

    /// 接收实时输入电平供调用链保持兼容；水墨 UI 不再在胶囊上暴露工程读数。
    func updateInputLevel(db: Float?) {
        _ = db
    }
}
