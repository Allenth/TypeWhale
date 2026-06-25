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

        infoBar.orientation = .horizontal
        infoBar.alignment = .centerY
        infoBar.spacing = 5
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.setViews([appIconView, appNameLabel, dotLabel, modeButton], in: .leading)
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
    func setContext(appIcon: NSImage?, appName: String?, modeName: String) {
        let rawName = (appName?.isEmpty == false) ? appName! : "未知应用"
        appNameLabel.stringValue = String(rawName.prefix(16))
        appIconView.image = appIcon
        appIconView.isHidden = (appIcon == nil)
        setModeTitle(modeName)
        hasContext = true
        infoBar.isHidden = false
        capsule.contextTopInset = infoBarHeight
        resizeAndPosition()
    }

    /// 仅更新模式标签（手动切换后调用），不改动 App 信息。
    func updateModeName(_ modeName: String) {
        setModeTitle(modeName)
        if hasContext { resizeAndPosition() }
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
}
