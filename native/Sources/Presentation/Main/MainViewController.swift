import AppKit
import ApplicationServices

final class MainViewController: NSViewController {
    enum PrimaryStatusTone {
        case idle
        case listening
        case processing
        case success
        case warning
        case error
    }

    private let contentWidth: CGFloat = 660
    private let contentHeight: CGFloat = 858
    private let leftColumnWidth: CGFloat = 212
    private let topInset: CGFloat = 38
    private let recentViewportHeight: CGFloat = 258
    private let brandIconVisibleSize: CGFloat = 64

    let status = label("等待录音", size: 15, weight: .semibold)
    let detail = label("Fn 录音", size: 12)
    let micStatus = label("检测中", size: 12, weight: .medium)
    let accessibilityStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyValue = label(
        HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding).displayName,
        size: 13,
        weight: .semibold
    )
    let secondaryHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)?.displayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let hotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let hotkeyResetButton = NSButton(title: "恢复 Fn", target: nil, action: nil)
    let secondaryHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let secondaryHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let modelValue = label("正在检查模型", size: 12, weight: .medium)
    let modelProgress = NSProgressIndicator()
    let modelInstallButton = NSButton(title: "安装模型", target: nil, action: nil)
    let realtime = BrandSwitch()
    let autoFinish = BrandSwitch()
    let duckSystemAudio = BrandSwitch()
    let launchAtLogin = BrandSwitch()
    let smartRewriteMode = NSPopUpButton()
    let deepSeekKeyButton = NSButton(title: "设置 Key", target: nil, action: nil)
    let promptSettingsButton = NSButton(title: "提示词", target: nil, action: nil)
    let developerTermsButton = NSButton(title: "术语", target: nil, action: nil)
    let autoTranslate = BrandSwitch()
    let translationDirectionMode = NSPopUpButton()
    let translationPromptButton = NSButton(title: "提示词", target: nil, action: nil)
    let realtimeDraft = label("等待实时草稿", size: 12)
    var onInstallModel: (() -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?) -> Void)?

    private let modelEntryName = label("SenseVoice int8", size: 13, weight: .semibold)
    private let modelEntryStatus = label("检查中", size: 11, weight: .medium)
    private let modelEntryDot = NSView()
    private let modelPathLabel = label("", size: 11)
    private let statusDot = NSView()
    private let waveform = MiniWaveformView()
    private let processingProgress = NSProgressIndicator()

    private let recentStack = FlippedStackView()
    private let recentScroll = NSScrollView()
    private var recentRecords: [RecentTranscription] = []
    private var isCapturingHotkey = false
    private var capturingChannel: SpeechInputChannel?
    private var capturingHotkeySlot: HotkeySlot?
    private var hotkeyCaptureMonitor: Any?
    private var hotkeyCaptureTap: CFMachPort?
    private var hotkeyCaptureSource: CFRunLoopSource?
    private var captureModifierKeyCodes: Set<Int> = []
    private var captureConfirmWorkItem: DispatchWorkItem?
    private var versionHistoryPopover: NSPopover?
    private var modelDetailPopover: NSPopover?
    private lazy var versionHistoryViewController = VersionHistoryViewController()

    private enum HotkeySlot {
        case primary
        case secondary
    }

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        view = root
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: contentWidth),
            view.heightAnchor.constraint(equalToConstant: contentHeight),
        ])

        let darkOverlay = NSView()
        darkOverlay.translatesAutoresizingMaskIntoConstraints = false
        darkOverlay.wantsLayer = true
        darkOverlay.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.36).cgColor
        view.addSubview(darkOverlay)
        NSLayoutConstraint.activate([
            darkOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            darkOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            darkOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            darkOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let settings = AppSettingsStore.loadMainViewSettings()
        realtime.state = settings.realtimePreviewEnabled ? .on : .off
        realtime.target = self; realtime.action = #selector(saveSettings)
        autoFinish.state = settings.autoFinishAfterPauseEnabled ? .on : .off
        autoFinish.target = self; autoFinish.action = #selector(saveSettings)
        duckSystemAudio.state = settings.duckSystemAudioWhileRecordingEnabled ? .on : .off
        duckSystemAudio.target = self; duckSystemAudio.action = #selector(saveSettings)
        configureSmartRewriteModeMenu(settings.smartRewritePreference)
        smartRewriteMode.target = self; smartRewriteMode.action = #selector(saveSettings)
        configureDeepSeekKeyButton()
        configurePromptSettingsButton()
        configureDeveloperTermsButton()
        autoTranslate.state = settings.autoTranslateEnabled ? .on : .off
        autoTranslate.target = self; autoTranslate.action = #selector(saveSettings)
        configureTranslationDirectionMenu(settings.translationDirection)
        configureTranslationPromptButton()
        translationDirectionMode.target = self; translationDirectionMode.action = #selector(saveSettings)
        refreshLaunchAtLoginState()
        launchAtLogin.target = self; launchAtLogin.action = #selector(toggleLaunchAtLogin)
        configureOptionAccessibility()

        let left = buildLeftColumn()
        let right = buildRightColumn()
        view.addSubview(left)
        view.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.topAnchor.constraint(equalTo: view.topAnchor),
            left.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftColumnWidth),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 22),
            right.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            right.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            right.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])

        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        )
        DispatchQueue.main.async { [weak self] in
            _ = self?.versionHistoryViewController.view
        }
    }

    // MARK: - Left column

    private func buildLeftColumn() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = UITheme.brandTint.cgColor

        let border = NSView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.backgroundColor = UITheme.cardBorder.cgColor
        container.addSubview(border)

        let brandIcon = NSImageView()
        brandIcon.image = loadBrandIcon()
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.wantsLayer = true
        brandIcon.layer?.cornerRadius = 15
        brandIcon.layer?.masksToBounds = true
        let brandTitle = label("TypeWhale", size: 18, weight: .semibold)
        brandTitle.alignment = .center
        let brandVersion = label(versionText(), size: 11, weight: .medium)
        brandVersion.textColor = .secondaryLabelColor
        brandVersion.alignment = .center
        let brandStack = NSStackView(views: [brandIcon, brandTitle, brandVersion])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 6

        let statusPanel = buildStatusPanel()
        let modelEntry = buildModelEntry()
        let draftEntry = buildRealtimeDraftEntry()
        draftEntry.setContentHuggingPriority(.required, for: .vertical)
        draftEntry.setContentCompressionResistancePriority(.required, for: .vertical)

        let historyButton = NSButton(title: " 版本历史", target: self, action: #selector(showVersionHistory(_:)))
        historyButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        historyButton.imagePosition = .imageLeading
        historyButton.bezelStyle = .rounded
        historyButton.controlSize = .regular

        let usageGuide = buildUsageGuideEntry()
        usageGuide.setContentHuggingPriority(.required, for: .vertical)
        usageGuide.setContentCompressionResistancePriority(.required, for: .vertical)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [brandStack, statusPanel, modelEntry, draftEntry, spacer, usageGuide, historyButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: container.topAnchor),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 0.5),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            brandStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            draftEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            usageGuide.widthAnchor.constraint(equalTo: stack.widthAnchor),
            draftEntry.heightAnchor.constraint(equalToConstant: 108),
            historyButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            brandIcon.widthAnchor.constraint(equalToConstant: brandIconVisibleSize),
            brandIcon.heightAnchor.constraint(equalToConstant: brandIconVisibleSize),
        ])
        return container
    }

    private func buildStatusPanel() -> NSView {
        status.alignment = .center
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor

        let pillStack = NSStackView(views: [statusDot, status])
        pillStack.orientation = .horizontal
        pillStack.alignment = .centerY
        pillStack.spacing = 7
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        pill.layer?.cornerRadius = 12
        pill.addSubview(pillStack)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.style = .bar
        processingProgress.controlSize = .small
        processingProgress.isIndeterminate = true
        processingProgress.isDisplayedWhenStopped = false
        processingProgress.isHidden = true

        let inner = NSStackView(views: [pill, waveform, processingProgress, detail])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.spacing = 11
        inner.detachesHiddenViews = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = UITheme.cardFill.cgColor
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = UITheme.cardBorder.cgColor
        box.addSubview(inner)

        NSLayoutConstraint.activate([
            pillStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 13),
            pillStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -13),
            pillStack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            pillStack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
            waveform.heightAnchor.constraint(equalToConstant: 34),
            waveform.widthAnchor.constraint(equalTo: inner.widthAnchor),
            processingProgress.widthAnchor.constraint(equalTo: inner.widthAnchor, multiplier: 0.78),
            processingProgress.heightAnchor.constraint(equalToConstant: 4),
            box.heightAnchor.constraint(equalToConstant: 128),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            detail.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return box
    }

    private func buildModelEntry() -> NSView {
        let caption = label("当前模型", size: 10, weight: .medium)
        caption.textColor = UITheme.sectionTitle
        modelEntryName.maximumNumberOfLines = 1
        modelEntryName.lineBreakMode = .byTruncatingTail

        let chevron = symbolIcon("chevron.right", size: 12, color: NSColor(calibratedWhite: 1, alpha: 0.35))
        let nameRow = NSStackView(views: [modelEntryName, flexSpacer(), chevron])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8

        modelEntryDot.translatesAutoresizingMaskIntoConstraints = false
        modelEntryDot.wantsLayer = true
        modelEntryDot.layer?.cornerRadius = 3
        modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        modelEntryStatus.textColor = .secondaryLabelColor
        let statusRow = NSStackView(views: [modelEntryDot, modelEntryStatus])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 5

        let textStack = NSStackView(views: [caption, nameRow, statusRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let box = roundedBox(textStack, hPad: 14, vPad: 12)
        NSLayoutConstraint.activate([
            modelEntryDot.widthAnchor.constraint(equalToConstant: 6),
            modelEntryDot.heightAnchor.constraint(equalToConstant: 6),
            nameRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(showModelDetail(_:)))
        box.addGestureRecognizer(click)
        return box
    }

    private func buildRealtimeDraftEntry() -> NSView {
        realtimeDraft.textColor = .secondaryLabelColor
        realtimeDraft.maximumNumberOfLines = 4
        realtimeDraft.lineBreakMode = .byWordWrapping
        (realtimeDraft.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        realtimeDraft.translatesAutoresizingMaskIntoConstraints = false

        let draftContent = NSView()
        draftContent.translatesAutoresizingMaskIntoConstraints = false
        draftContent.addSubview(realtimeDraft)
        NSLayoutConstraint.activate([
            realtimeDraft.leadingAnchor.constraint(equalTo: draftContent.leadingAnchor),
            realtimeDraft.trailingAnchor.constraint(equalTo: draftContent.trailingAnchor),
            realtimeDraft.topAnchor.constraint(equalTo: draftContent.topAnchor),
            realtimeDraft.bottomAnchor.constraint(lessThanOrEqualTo: draftContent.bottomAnchor),
            draftContent.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        return section("实时草稿", roundedBox(draftContent, hPad: 12, vPad: 10))
    }

    private func buildUsageGuideEntry() -> NSView {
        let title = label("使用方法", size: 11, weight: .semibold)
        title.textColor = UITheme.sectionTitle

        let body = label(
            """
            先开启麦克风和辅助功能。
            按 Fn 开始录音，再按一次或松开结束。
            首次打开测试版：右键 App 选“打开”；若被拦截，到 系统设置 > 隐私与安全性，点“仍要打开”。
            """,
            size: 10
        )
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return roundedBox(stack, hPad: 12, vPad: 10)
    }

    // MARK: - Right column

    private func buildRightColumn() -> NSView {
        let micButton = settingsButton("设置", action: #selector(openMicrophone))
        let accessButton = settingsButton("设置", action: #selector(openAccessibility))
        let keyboardButton = settingsButton("设置", action: #selector(openKeyboard))
        let permissionCard = listCard([
            permissionRow(icon: "mic", name: "麦克风", status: micStatus, button: micButton),
            permissionRow(icon: "accessibility", name: "辅助功能", status: accessibilityStatus, button: accessButton),
            permissionRow(icon: "keyboard", name: "全局快捷键", status: hotkeyStatus, button: keyboardButton),
        ])

        [hotkeyValue, secondaryHotkeyValue].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
        }
        hotkeyCaptureButton.target = self
        hotkeyCaptureButton.action = #selector(beginHotkeyCapture)
        hotkeyResetButton.target = self
        hotkeyResetButton.action = #selector(resetHotkey)
        secondaryHotkeyCaptureButton.target = self
        secondaryHotkeyCaptureButton.action = #selector(beginSecondaryHotkeyCapture)
        secondaryHotkeyClearButton.target = self
        secondaryHotkeyClearButton.action = #selector(clearSecondaryHotkey)
        let hotkeyButtons = [hotkeyCaptureButton, hotkeyResetButton, secondaryHotkeyCaptureButton, secondaryHotkeyClearButton]
        hotkeyButtons.forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
            $0.font = .systemFont(ofSize: 12)
        }
        let captureWidth: CGFloat = 124
        let trailingWidth: CGFloat = 96
        [hotkeyCaptureButton, secondaryHotkeyCaptureButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: captureWidth).isActive = true
        }
        [hotkeyResetButton, secondaryHotkeyClearButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: trailingWidth).isActive = true
        }
        let primaryRow = shortcutRow(
            title: "主快捷键",
            captureButton: hotkeyCaptureButton,
            fallbackButton: hotkeyResetButton
        )
        let secondaryRow = shortcutRow(
            title: "备用快捷键",
            captureButton: secondaryHotkeyCaptureButton,
            fallbackButton: secondaryHotkeyClearButton
        )
        let hotkeyCard = listCard([primaryRow, secondaryRow], hPad: 12)
        hotkeyCard.setContentCompressionResistancePriority(.required, for: .vertical)

        let smartRewriteControls = NSStackView(views: [smartRewriteMode, promptSettingsButton, developerTermsButton, deepSeekKeyButton])
        smartRewriteControls.orientation = .horizontal
        smartRewriteControls.alignment = .centerY
        smartRewriteControls.spacing = 6
        promptSettingsButton.widthAnchor.constraint(equalToConstant: 62).isActive = true
        developerTermsButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        deepSeekKeyButton.widthAnchor.constraint(equalToConstant: 74).isActive = true

        let translationControls = NSStackView(views: [translationDirectionMode, translationPromptButton])
        translationControls.orientation = .horizontal
        translationControls.alignment = .centerY
        translationControls.spacing = 6
        translationPromptButton.widthAnchor.constraint(equalToConstant: 62).isActive = true

        let optionCard = listCard([
            optionRow("智能整理", smartRewriteControls),
            optionRow("自动翻译", autoTranslate),
            optionRow("翻译方向", translationControls),
            optionRow("胶囊实时预览", realtime),
            optionRow("停顿自动完成", autoFinish),
            optionRow("录音时降低电脑声音", duckSystemAudio),
            optionRow("开机自动启动", launchAtLogin),
        ])

        recentStack.orientation = .vertical
        recentStack.alignment = .width
        recentStack.spacing = 0
        recentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentRecords = loadRecentTranscriptions()
        rebuildRecentRows()
        recentScroll.documentView = recentStack
        recentScroll.hasVerticalScroller = true
        recentScroll.autohidesScrollers = true
        recentScroll.drawsBackground = false
        recentScroll.borderType = .noBorder
        recentScroll.translatesAutoresizingMaskIntoConstraints = false
        recentScroll.heightAnchor.constraint(equalToConstant: recentViewportHeight).isActive = true
        let recentCard = roundedBox(recentScroll, hPad: 8, vPad: 6)

        let sections = [
            section("权限", permissionCard),
            section("快捷键", hotkeyCard),
            section("选项", optionCard),
            section("最近转录", recentCard),
        ]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for sectionView in sections {
            sectionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        recentStack.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor).isActive = true
        return stack
    }

    private func section(_ title: String, _ card: NSView) -> NSView {
        let stack = NSStackView(views: [sectionHeader(title), card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func settingsButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12)
        button.widthAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    private func permissionRow(icon: String, name: String, status: NSTextField, button: NSButton) -> NSView {
        let iconView = symbolIcon(icon, size: 16)
        let nameLabel = label(name, size: 14)
        status.alignment = .left
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.required, for: .horizontal)
        status.widthAnchor.constraint(equalToConstant: 86).isActive = true
        let row = NSStackView(views: [iconView, nameLabel, flexSpacer(), status, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    private func shortcutRow(
        title: String,
        captureButton: NSButton,
        fallbackButton: NSButton
    ) -> NSView {
        let titleLabel = label(title, size: 14)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, flexSpacer(), captureButton, fallbackButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        row.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return row
    }

    private func optionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 14)
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    private func configureOptionAccessibility() {
        smartRewriteMode.setAccessibilityLabel("智能整理")
        deepSeekKeyButton.setAccessibilityLabel("DeepSeek API Key")
        promptSettingsButton.setAccessibilityLabel("智能整理提示词")
        developerTermsButton.setAccessibilityLabel("开发术语词库")
        autoTranslate.setAccessibilityLabel("自动翻译")
        autoTranslate.toolTip = "可用 Shift + \\ 快速打开或关闭"
        translationDirectionMode.setAccessibilityLabel("翻译方向")
        translationPromptButton.setAccessibilityLabel("翻译提示词")
        realtime.setAccessibilityLabel("胶囊实时预览")
        autoFinish.setAccessibilityLabel("停顿自动完成")
        duckSystemAudio.setAccessibilityLabel("录音时降低电脑声音")
        launchAtLogin.setAccessibilityLabel("开机自动启动")
    }

    private func configureSmartRewriteModeMenu(_ preference: SmartRewritePreference) {
        smartRewriteMode.removeAllItems()
        for item in SmartRewritePreference.allCases {
            smartRewriteMode.addItem(withTitle: item.displayName)
            smartRewriteMode.lastItem?.tag = item.menuTag
        }
        smartRewriteMode.selectItem(withTag: preference.menuTag)
        smartRewriteMode.toolTip = "最终识别后、粘贴前的文本整理模式"
        smartRewriteMode.bezelStyle = .rounded
        smartRewriteMode.controlSize = .regular
        smartRewriteMode.font = .systemFont(ofSize: 12)
    }

    private func configureDeepSeekKeyButton() {
        deepSeekKeyButton.target = self
        deepSeekKeyButton.action = #selector(configureDeepSeekAPIKey)
        deepSeekKeyButton.bezelStyle = .rounded
        deepSeekKeyButton.controlSize = .regular
        deepSeekKeyButton.font = .systemFont(ofSize: 12, weight: .medium)
        deepSeekKeyButton.toolTip = "录入 DeepSeek API Key，保存到 macOS Keychain"
        refreshDeepSeekKeyButton()
    }

    private func configurePromptSettingsButton() {
        promptSettingsButton.target = self
        promptSettingsButton.action = #selector(configureSmartRewritePrompts)
        promptSettingsButton.bezelStyle = .rounded
        promptSettingsButton.controlSize = .regular
        promptSettingsButton.font = .systemFont(ofSize: 12, weight: .medium)
        promptSettingsButton.toolTip = "调整、修改并保存智能整理提示词"
    }

    private func configureDeveloperTermsButton() {
        developerTermsButton.target = self
        developerTermsButton.action = #selector(configureDeveloperTerms)
        developerTermsButton.bezelStyle = .rounded
        developerTermsButton.controlSize = .regular
        developerTermsButton.font = .systemFont(ofSize: 12, weight: .medium)
        developerTermsButton.toolTip = "管理开发术语和别名"
    }

    private func configureTranslationPromptButton() {
        translationPromptButton.target = self
        translationPromptButton.action = #selector(configureTranslationPrompts)
        translationPromptButton.bezelStyle = .rounded
        translationPromptButton.controlSize = .regular
        translationPromptButton.font = .systemFont(ofSize: 12, weight: .medium)
        translationPromptButton.toolTip = "调整、修改并保存自动翻译提示词"
    }

    private func refreshDeepSeekKeyButton() {
        deepSeekKeyButton.title = DeepSeekAPIKeyStore.hasAPIKey() ? "Key 已设" : "设置 Key"
    }

    func toggleAutoTranslateFromShortcut() {
        autoTranslate.state = autoTranslate.state == .on ? .off : .on
        autoTranslate.needsDisplay = true
        saveSettings()
        let stateText = autoTranslate.state == .on ? "已开启" : "已关闭"
        detail.stringValue = "自动翻译\(stateText) · Shift + \\"
    }

    private func configureTranslationDirectionMenu(_ direction: SmartTranslationDirection) {
        translationDirectionMode.removeAllItems()
        for item in SmartTranslationDirection.allCases {
            translationDirectionMode.addItem(withTitle: item.displayName)
            translationDirectionMode.lastItem?.tag = item.menuTag
        }
        translationDirectionMode.selectItem(withTag: direction.menuTag)
        translationDirectionMode.toolTip = "自动翻译开启后使用的转换方向"
        translationDirectionMode.bezelStyle = .rounded
        translationDirectionMode.controlSize = .regular
        translationDirectionMode.font = .systemFont(ofSize: 12)
    }

    private func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.40"
        let build = info?["CFBundleVersion"] as? String ?? "197"
        return "Version \(version) (\(build))"
    }

    private func loadBrandIcon() -> NSImage? {
        guard let image = loadAppIcon() else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let unit: CGFloat = 1024
        let cropRect = CGRect(
            x: CGFloat(cgImage.width) * 148 / unit,
            y: CGFloat(cgImage.height) * 143 / unit,
            width: CGFloat(cgImage.width) * 728 / unit,
            height: CGFloat(cgImage.height) * 728 / unit
        ).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: brandIconVisibleSize, height: brandIconVisibleSize))
    }

    private func loadAppIcon() -> NSImage? {
        if let image = NSImage(named: "TypeWhale") {
            return image
        }
        if let url = Bundle.main.url(forResource: "TypeWhale", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    @objc private func showVersionHistory(_ sender: NSButton) {
        if let popover = versionHistoryPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = versionHistoryPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 390)
        popover.contentViewController = versionHistoryViewController
        versionHistoryPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc private func showModelDetail(_ sender: NSGestureRecognizer) {
        guard let anchor = sender.view else { return }
        if let popover = modelDetailPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = modelDetailPopover ?? NSPopover()
        if modelDetailPopover == nil {
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 300, height: 240)
            popover.contentViewController = makeModelDetailController()
            modelDetailPopover = popover
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    private func makeModelDetailController() -> NSViewController {
        let icon = symbolIcon("cpu", size: 18, color: UITheme.brandYellow)
        let title = label("SenseVoice int8", size: 14, weight: .semibold)
        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping

        let desc = label("本地离线语音识别模型，全程在本机推理，不上传音频。", size: 12)
        desc.textColor = .secondaryLabelColor
        desc.maximumNumberOfLines = 0
        desc.lineBreakMode = .byWordWrapping

        let pathCaption = label("模型位置", size: 11, weight: .medium)
        pathCaption.textColor = UITheme.sectionTitle
        modelPathLabel.textColor = .secondaryLabelColor
        modelPathLabel.maximumNumberOfLines = 3
        modelPathLabel.lineBreakMode = .byCharWrapping

        modelProgress.isIndeterminate = false
        modelProgress.minValue = 0
        modelProgress.maxValue = 1
        modelProgress.controlSize = .small
        modelProgress.isHidden = true
        modelInstallButton.target = self
        modelInstallButton.action = #selector(installModel)
        modelInstallButton.isHidden = true
        modelInstallButton.bezelStyle = .rounded
        let installRow = NSStackView(views: [flexSpacer(), modelInstallButton])
        installRow.orientation = .horizontal

        let stack = NSStackView(views: [titleRow, hairlineView(), modelValue, modelProgress, desc, pathCaption, modelPathLabel, installRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 268),
            modelValue.widthAnchor.constraint(equalTo: stack.widthAnchor),
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelPathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            installRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let controller = NSViewController()
        controller.view = content
        return controller
    }

    @objc private func saveSettings() {
        if autoFinish.state == .on {
            realtime.state = .on
            realtime.needsDisplay = true
        }
        if realtime.state == .off {
            autoFinish.state = .off
            autoFinish.needsDisplay = true
        }
        AppSettingsStore.save(MainViewSettings(
            realtimePreviewEnabled: realtime.state == .on,
            autoFinishAfterPauseEnabled: autoFinish.state == .on,
            duckSystemAudioWhileRecordingEnabled: duckSystemAudio.state == .on,
            smartRewritePreference: smartRewritePreference,
            autoTranslateEnabled: autoTranslate.state == .on,
            translationDirection: translationDirection
        ))
    }

    @objc private func configureSmartRewritePrompts() {
        let dialog = SmartRewritePromptDialog(initialMode: smartRewritePreference.manualMode ?? .developerRequirement)
        switch dialog.runModal() {
        case .save(let mode, let template):
            SmartRewritePromptStore.save(template, for: mode)
            detail.stringValue = "\(mode.displayName)提示词已保存"
        case .reset(let mode):
            SmartRewritePromptStore.reset(mode)
            detail.stringValue = "\(mode.displayName)提示词已恢复默认"
        case .cancel:
            break
        }
    }

    @objc private func configureTranslationPrompts() {
        let dialog = SmartTranslationPromptDialog(initialDirection: translationDirection)
        switch dialog.runModal() {
        case .save(let direction, let template):
            SmartTranslationPromptStore.save(template, for: direction)
            detail.stringValue = "\(direction.displayName)提示词已保存"
        case .reset(let direction):
            SmartTranslationPromptStore.reset(direction)
            detail.stringValue = "\(direction.displayName)提示词已恢复默认"
        case .cancel:
            break
        }
    }

    @objc private func configureDeveloperTerms() {
        switch DeveloperLexiconDialog().runModal() {
        case .save(let terms):
            DeveloperLexiconStore.save(terms)
            detail.stringValue = "开发术语词库已保存"
        case .reset:
            DeveloperLexiconStore.restoreDefaults()
            detail.stringValue = "开发术语词库已恢复默认"
        case .cancel:
            break
        }
    }

    @objc private func configureDeepSeekAPIKey() {
        let alert = NSAlert()
        alert.messageText = "DeepSeek API Key"
        alert.informativeText = "用于智能整理和自动翻译，保存到 macOS Keychain。TypeWhale 使用 deepseek-v4-flash，并关闭 thinking。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = DeepSeekAPIKeyStore.hasAPIKey() ? "已保存 Key，输入新 Key 可覆盖" : "sk-..."
        alert.accessoryView = input

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try DeepSeekAPIKeyStore.save(input.stringValue)
                refreshDeepSeekKeyButton()
                detail.stringValue = DeepSeekAPIKeyStore.hasAPIKey()
                    ? "DeepSeek Key 已保存，智能整理已启用"
                    : "未输入 Key，智能整理会回退原文"
            } catch {
                showDeepSeekKeyError(error)
            }
        case .alertSecondButtonReturn:
            DeepSeekAPIKeyStore.delete()
            refreshDeepSeekKeyButton()
            detail.stringValue = "DeepSeek Key 已清除，智能整理会回退原文"
        default:
            refreshDeepSeekKeyButton()
        }
    }

    private func showDeepSeekKeyError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "DeepSeek Key 保存失败"
        alert.runModal()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItemManager.setEnabled(launchAtLogin.state == .on)
            refreshLaunchAtLoginState()
            if LoginItemManager.isPendingApproval {
                detail.stringValue = "请在系统设置的登录项中允许 TypeWhale"
            }
        } catch {
            refreshLaunchAtLoginState()
            detail.stringValue = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    private func refreshLaunchAtLoginState() {
        launchAtLogin.state = (LoginItemManager.isEnabled || LoginItemManager.isPendingApproval) ? .on : .off
        launchAtLogin.needsDisplay = true
        launchAtLogin.toolTip = LoginItemManager.isPendingApproval
            ? "已提交开机启动请求，请在系统设置的登录项中允许 TypeWhale"
            : "登录 macOS 后自动启动 TypeWhale"
    }

    @objc private func beginHotkeyCapture() {
        beginHotkeyCaptureForSlot(.primary)
    }

    @objc private func beginSecondaryHotkeyCapture() {
        beginHotkeyCaptureForSlot(.secondary)
    }

    private func beginHotkeyCaptureForSlot(_ slot: HotkeySlot) {
        guard !isCapturingHotkey else { return }
        isCapturingHotkey = true
        capturingChannel = .chinese
        capturingHotkeySlot = slot
        captureModifierKeyCodes.removeAll()
        activeHotkeyButton?.title = "请按快捷键…"
        hotkeyCaptureButton.isEnabled = false
        secondaryHotkeyCaptureButton.isEnabled = false
        startHotkeyCaptureTap()
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            self.capture(event: event)
            return nil
        }
    }

    @objc private func resetHotkey() {
        applyHotkey(.defaultBinding, slot: .primary, channel: .chinese)
    }

    @objc private func clearSecondaryHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: nil
        )
        onHotkeysChange?(
            HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            nil
        )
    }

    func updateHotkeys(primary: HotkeyBinding, secondary: HotkeyBinding?) {
        hotkeyValue.stringValue = primary.displayName
        hotkeyValue.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        hotkeyCaptureButton.title = primary.displayName
        hotkeyCaptureButton.toolTip = "点击录入主快捷键"
        secondaryHotkeyValue.stringValue = secondary?.displayName ?? "未设置"
        secondaryHotkeyValue.textColor = secondary == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        secondaryHotkeyCaptureButton.title = secondary?.displayName ?? "未设置"
        secondaryHotkeyCaptureButton.toolTip = "点击录入备用快捷键"
        detail.stringValue = "\(primary.displayName) 录音"
    }

    func updateHotkey(_ binding: HotkeyBinding) {
        updateHotkeys(primary: binding, secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey))
    }

    private func startHotkeyCaptureTap() {
        stopHotkeyCaptureTap()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        hotkeyCaptureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<MainViewController>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = controller.hotkeyCaptureTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if controller.capture(event: event, type: type) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let hotkeyCaptureTap else { return }
        hotkeyCaptureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hotkeyCaptureTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), hotkeyCaptureSource, .commonModes)
        CGEvent.tapEnable(tap: hotkeyCaptureTap, enable: true)
    }

    private func stopHotkeyCaptureTap() {
        if let hotkeyCaptureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeyCaptureSource, .commonModes)
        }
        hotkeyCaptureSource = nil
        hotkeyCaptureTap = nil
    }

    private func capture(event: CGEvent, type: CGEventType) -> Bool {
        guard isCapturingHotkey else { return false }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            if keyCode == HotkeyKeyCodes.function || event.flags.contains(.maskSecondaryFn) {
                captureFunctionKey()
                return true
            }
            captureModifier(keyCode: keyCode, cgFlags: event.flags)
            return true
        }
        guard type == .keyDown else { return false }
        if keyCode == 53 {
            captureConfirmWorkItem?.cancel()
            endHotkeyCapture()
            refreshHotkeyLabels()
            return true
        }
        captureConfirmWorkItem?.cancel()
        if captureModifierKeyCodes.isEmpty {
            captureModifierKeyCodes = HotkeyKeyCodes.fallbackModifierKeyCodes(from: event.flags)
        }
        commitCapturedHotkey(keyCode: keyCode)
        return true
    }

    private func capture(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        if event.type == .flagsChanged {
            if keyCode == HotkeyKeyCodes.function || event.modifierFlags.contains(.function) {
                captureFunctionKey()
                return
            }
            captureModifier(keyCode: keyCode, modifierFlags: event.modifierFlags)
            return
        }

        if keyCode == 53 {
            captureConfirmWorkItem?.cancel()
            endHotkeyCapture()
            refreshHotkeyLabels()
            return
        }
        captureConfirmWorkItem?.cancel()
        if captureModifierKeyCodes.isEmpty {
            captureModifierKeyCodes = HotkeyKeyCodes.fallbackModifierKeyCodes(from: event.modifierFlags)
        }
        commitCapturedHotkey(keyCode: keyCode)
    }

    private func captureModifier(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.modifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && modifierFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    private func captureModifier(keyCode: Int, cgFlags: CGEventFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && cgFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    private func captureModifier(keyCode: Int, isPressed: Bool) {
        if isPressed {
            captureModifierKeyCodes.insert(keyCode)
            if capturingChannel != nil {
                activeHotkeyButton?.title = "\(HotkeyKeyCodes.displayName(for: keyCode)) …"
            }
            scheduleModifierCaptureConfirmation(keyCode: keyCode)
        } else {
            captureConfirmWorkItem?.cancel()
            commitCapturedHotkey(keyCode: keyCode)
        }
    }

    private func captureFunctionKey() {
        guard capturingChannel != nil else { return }
        activeHotkeyButton?.title = "Fn …"
        captureModifierKeyCodes = []
        commitCapturedHotkey(keyCode: HotkeyKeyCodes.function)
    }

    private func scheduleModifierCaptureConfirmation(keyCode: Int, delay: TimeInterval = 0.45) {
        captureConfirmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturingHotkey else { return }
            self.commitCapturedHotkey(keyCode: keyCode)
        }
        captureConfirmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func commitCapturedHotkey(keyCode: Int) {
        guard let capturingChannel else { return }
        guard let binding = HotkeyBinding.fromCapture(keyCode: keyCode, modifierKeyCodes: captureModifierKeyCodes) else {
            showCaptureError("请加 Cmd/Option/Control", channel: capturingChannel)
            return
        }
        applyCapturedHotkey(binding)
    }

    private func showCaptureError(_ message: String, channel: SpeechInputChannel) {
        captureConfirmWorkItem?.cancel()
        activeHotkeyButton?.title = message
    }

    private func applyCapturedHotkey(_ binding: HotkeyBinding) {
        guard let capturingChannel, let capturingHotkeySlot else { return }
        applyHotkey(binding, slot: capturingHotkeySlot, channel: capturingChannel)
    }

    private func applyHotkey(_ binding: HotkeyBinding, slot: HotkeySlot, channel: SpeechInputChannel) {
        endHotkeyCapture()
        switch slot {
        case .primary:
            binding.save(storageKey: HotkeyBinding.chineseStorageKey)
        case .secondary:
            binding.save(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        }
        let primary = HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding)
        let secondary = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        updateHotkeys(primary: primary, secondary: secondary)
        onHotkeysChange?(primary, secondary)
    }

    private func endHotkeyCapture() {
        captureConfirmWorkItem?.cancel()
        captureConfirmWorkItem = nil
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
        }
        hotkeyCaptureMonitor = nil
        stopHotkeyCaptureTap()
        isCapturingHotkey = false
        capturingChannel = nil
        capturingHotkeySlot = nil
        hotkeyCaptureButton.isEnabled = true
        secondaryHotkeyCaptureButton.isEnabled = true
        captureModifierKeyCodes.removeAll()
    }

    private func refreshHotkeyLabels() {
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        )
    }

    private var activeHotkeyButton: NSButton? {
        switch capturingHotkeySlot {
        case .primary:
            return hotkeyCaptureButton
        case .secondary:
            return secondaryHotkeyCaptureButton
        case nil:
            return nil
        }
    }

    @objc private func installModel() {
        onInstallModel?()
    }

    func updateModelState(_ state: SenseVoiceModelInstaller.State) {
        switch state {
        case .missing:
            modelEntryStatus.stringValue = "未安装"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = nil
            modelValue.stringValue = "SenseVoice int8 缺失，请先安装"
            modelValue.textColor = .systemRed
            modelPathLabel.stringValue = "—"
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "安装模型"
        case .ready:
            let sensePath = SenseVoiceModelManifest.preferredModelDirectory?.path ?? ""
            modelEntryStatus.stringValue = "已就绪"
            modelEntryStatus.textColor = .systemGreen
            modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            modelValue.toolTip = sensePath
            modelValue.stringValue = "本地模型已就绪，可离线识别"
            modelValue.textColor = .systemGreen
            modelPathLabel.stringValue = sensePath.isEmpty ? "内置模型" : sensePath
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
        case .downloading(let progress):
            modelEntryStatus.stringValue = "安装中 \(Int(progress * 100))%"
            modelEntryStatus.textColor = .secondaryLabelColor
            modelEntryDot.layer?.backgroundColor = UITheme.brandYellow.cgColor
            modelValue.toolTip = nil
            modelValue.stringValue = "正在安装 SenseVoice · \(Int(progress * 100))%"
            modelValue.textColor = .secondaryLabelColor
            modelProgress.doubleValue = progress
            modelProgress.isHidden = false
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = false
            modelInstallButton.title = "安装中"
        case .failed(let message):
            modelEntryStatus.stringValue = "安装失败"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = message
            modelValue.stringValue = message
            modelValue.textColor = .systemRed
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "重试安装"
        }
    }

    func updateInputBands(_ bands: [Float]) {
        waveform.update(bands)
    }

    func resetInputBands() {
        waveform.reset()
    }

    func setPrimaryStatus(
        _ text: String,
        detail detailText: String? = nil,
        tone: PrimaryStatusTone,
        resetWaveform: Bool = false
    ) {
        status.stringValue = text
        if let detailText {
            detail.stringValue = detailText
        }
        statusDot.layer?.backgroundColor = statusColor(for: tone).cgColor
        if tone == .processing {
            processingProgress.isHidden = false
            processingProgress.startAnimation(nil)
        } else {
            processingProgress.stopAnimation(nil)
            processingProgress.isHidden = true
        }
        if resetWaveform {
            resetInputBands()
        }
    }

    private func statusColor(for tone: PrimaryStatusTone) -> NSColor {
        switch tone {
        case .idle, .success:
            return .systemGreen
        case .listening, .processing:
            return UITheme.brandYellow
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    @objc private func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openKeyboard() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    var realtimePreviewEnabled: Bool {
        realtime.state == .on
    }

    var autoFinishAfterPauseEnabled: Bool {
        autoFinish.state == .on
    }

    var duckSystemAudioWhileRecordingEnabled: Bool {
        duckSystemAudio.state == .on
    }

    var smartRewritePreference: SmartRewritePreference {
        SmartRewritePreference.fromMenuTag(smartRewriteMode.selectedItem?.tag ?? 0)
    }

    var autoTranslateEnabled: Bool {
        autoTranslate.state == .on
    }

    var translationDirection: SmartTranslationDirection {
        SmartTranslationDirection.fromMenuTag(translationDirectionMode.selectedItem?.tag ?? 0)
    }

    func addRecentTranscription(
        _ text: String,
        recognitionSeconds: Double,
        sourceText: String? = nil,
        translatedText: String? = nil,
        translationDirection: SmartTranslationDirection? = nil,
        usage: SmartUsage? = nil
    ) {
        guard !text.isEmpty else { return }
        let record = RecentTranscription(
            text: text,
            recognitionSeconds: recognitionSeconds,
            sourceText: sourceText,
            translatedText: translatedText,
            translationDirection: translationDirection,
            usage: usage
        )
        recentRecords.removeAll { $0.text == text }
        recentRecords.insert(record, at: 0)
        recentRecords = Array(recentRecords.prefix(5))
        saveRecentTranscriptions()
        rebuildRecentRows()
    }

    private func loadRecentTranscriptions() -> [RecentTranscription] {
        if let data = UserDefaults.standard.data(forKey: "recentTranscriptionRecords"),
           let records = try? JSONDecoder().decode([RecentTranscription].self, from: data) {
            return Array(records.prefix(5))
        }
        let legacy = UserDefaults.standard.stringArray(forKey: "recentTranscriptions") ?? []
        return Array(legacy.prefix(5)).map { RecentTranscription(text: $0, recognitionSeconds: nil) }
    }

    private func saveRecentTranscriptions() {
        if let data = try? JSONEncoder().encode(recentRecords) {
            UserDefaults.standard.set(data, forKey: "recentTranscriptionRecords")
        }
        UserDefaults.standard.set(recentRecords.map(\.text), forKey: "recentTranscriptions")
    }

    private func rebuildRecentRows() {
        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if recentRecords.isEmpty {
            let empty = label("尚无转录结果", size: 13)
            empty.textColor = .secondaryLabelColor
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            empty.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
                empty.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                empty.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            ])
            recentStack.addArrangedSubview(wrapper)
            return
        }
        for (index, record) in recentRecords.enumerated() {
            let metaLabel = label(record.timeText, size: 10, weight: .medium)
            metaLabel.textColor = .secondaryLabelColor
            metaLabel.maximumNumberOfLines = 1
            metaLabel.lineBreakMode = .byTruncatingTail
            metaLabel.translatesAutoresizingMaskIntoConstraints = false
            let usageLabel = label(record.usage?.compactText ?? "", size: 10, weight: .medium)
            usageLabel.textColor = UITheme.sectionTitle
            usageLabel.alignment = .right
            usageLabel.maximumNumberOfLines = 1
            usageLabel.lineBreakMode = .byTruncatingTail
            usageLabel.translatesAutoresizingMaskIntoConstraints = false
            usageLabel.isHidden = record.usage == nil

            let textLabel = label(displayText(for: record), size: 12)
            textLabel.maximumNumberOfLines = record.hasTranslation ? 5 : 3
            textLabel.lineBreakMode = .byWordWrapping
            (textLabel.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
            textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textLabel.translatesAutoresizingMaskIntoConstraints = false

            let copyButton = NSButton()
            copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
            copyButton.bezelStyle = .inline
            copyButton.isBordered = false
            copyButton.toolTip = "复制"
            copyButton.tag = index
            copyButton.target = self
            copyButton.action = #selector(copyRecent(_:))
            copyButton.translatesAutoresizingMaskIntoConstraints = false

            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(metaLabel)
            row.addSubview(usageLabel)
            row.addSubview(textLabel)
            row.addSubview(copyButton)
            recentStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: recentStack.widthAnchor),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: record.hasTranslation ? 86 : 64),
                metaLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                metaLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: usageLabel.leadingAnchor, constant: -8),
                usageLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                usageLabel.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
                usageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 112),
                textLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                textLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 5),
                textLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -9),
                textLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                copyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                copyButton.widthAnchor.constraint(equalToConstant: 24),
                copyButton.heightAnchor.constraint(equalToConstant: 24),
            ])
            if index < recentRecords.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                    divider.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                    divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                ])
            }
        }
    }

    @objc private func copyRecent(_ sender: NSButton) {
        guard recentRecords.indices.contains(sender.tag) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayText(for: recentRecords[sender.tag]), forType: .string)
    }

    private func displayText(for record: RecentTranscription) -> String {
        guard record.hasTranslation,
              let sourceText = record.sourceText,
              let translatedText = record.translatedText,
              let direction = record.translationDirection else {
            return record.text
        }
        return "\(direction.sourceLabel)：\(sourceText)\n\(direction.targetLabel)：\(translatedText)"
    }
}

private final class SmartRewritePromptDialog: NSObject {
    enum Result {
        case save(RewriteMode, String)
        case reset(RewriteMode)
        case cancel
    }

    private let modePicker = NSPopUpButton()
    private let textView = NSTextView()
    private var selectedMode: RewriteMode

    init(initialMode: RewriteMode) {
        selectedMode = SmartRewritePromptStore.editableModes.contains(initialMode) ? initialMode : .developerRequirement
        super.init()
    }

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "智能整理提示词"
        alert.informativeText = "选择一种整理模式，修改提示词后保存。可用占位符：{rawText}、{targetAppName}、{targetBundleIdentifier}。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTemplate(for: selectedMode)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(selectedMode, textView.string)
        case .alertSecondButtonReturn:
            return .reset(selectedMode)
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        modePicker.removeAllItems()
        for mode in SmartRewritePromptStore.editableModes {
            modePicker.addItem(withTitle: mode.displayName)
            modePicker.lastItem?.representedObject = mode.rawValue
        }
        modePicker.selectItem(withTitle: selectedMode.displayName)
        modePicker.target = self
        modePicker.action = #selector(modeDidChange)
        modePicker.bezelStyle = .rounded
        modePicker.controlSize = .regular

        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        textView.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedWhite: 1, alpha: 1)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 460, height: 300)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "保存空内容会恢复默认。若忘记 {rawText}，TypeWhale 会自动补到模板末尾。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [modePicker, scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            modePicker.widthAnchor.constraint(equalToConstant: 160),
            scrollView.widthAnchor.constraint(equalToConstant: 460),
            scrollView.heightAnchor.constraint(equalToConstant: 300),
            hint.widthAnchor.constraint(equalToConstant: 460),
        ])
        return container
    }

    @objc private func modeDidChange() {
        guard let rawValue = modePicker.selectedItem?.representedObject as? String,
              let mode = RewriteMode(rawValue: rawValue) else {
            return
        }
        selectedMode = mode
        loadTemplate(for: mode)
    }

    private func loadTemplate(for mode: RewriteMode) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: SmartRewritePromptStore.template(for: mode),
            attributes: attributes
        ))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}

private final class SmartTranslationPromptDialog: NSObject {
    enum Result {
        case save(SmartTranslationDirection, String)
        case reset(SmartTranslationDirection)
        case cancel
    }

    private let directionPicker = NSPopUpButton()
    private let textView = NSTextView()
    private var selectedDirection: SmartTranslationDirection

    init(initialDirection: SmartTranslationDirection) {
        selectedDirection = initialDirection
        super.init()
    }

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "翻译提示词"
        alert.informativeText = "选择翻译方向，修改语气和表达规则后保存。中译英提示词会影响英文翻译的口语化风格。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTemplate(for: selectedDirection)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(selectedDirection, textView.string)
        case .alertSecondButtonReturn:
            return .reset(selectedDirection)
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        directionPicker.removeAllItems()
        for direction in SmartTranslationDirection.allCases {
            directionPicker.addItem(withTitle: direction.displayName)
            directionPicker.lastItem?.representedObject = direction.rawValue
        }
        directionPicker.selectItem(withTitle: selectedDirection.displayName)
        directionPicker.target = self
        directionPicker.action = #selector(directionDidChange)
        directionPicker.bezelStyle = .rounded
        directionPicker.controlSize = .regular

        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        textView.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedWhite: 1, alpha: 1)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 460, height: 260)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "保存空内容会恢复默认。这里只写翻译语气和表达规则，原文会由 TypeWhale 自动附加。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [directionPicker, scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            directionPicker.widthAnchor.constraint(equalToConstant: 160),
            scrollView.widthAnchor.constraint(equalToConstant: 460),
            scrollView.heightAnchor.constraint(equalToConstant: 260),
            hint.widthAnchor.constraint(equalToConstant: 460),
        ])
        return container
    }

    @objc private func directionDidChange() {
        guard let rawValue = directionPicker.selectedItem?.representedObject as? String,
              let direction = SmartTranslationDirection(rawValue: rawValue) else {
            return
        }
        selectedDirection = direction
        loadTemplate(for: direction)
    }

    private func loadTemplate(for direction: SmartTranslationDirection) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: SmartTranslationPromptStore.template(for: direction),
            attributes: attributes
        ))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}

private final class DeveloperLexiconDialog: NSObject {
    enum Result {
        case save([DeveloperTerm])
        case reset
        case cancel
    }

    private let textView = NSTextView()

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "开发术语词库"
        alert.informativeText = "每行一个术语：标准词 | 分类 | 别名1, 别名2。新增、编辑或删除对应行即可管理词库。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTerms()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(parseTerms(from: textView.string))
        case .alertSecondButtonReturn:
            return .reset
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        textView.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedWhite: 1, alpha: 1)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "分类可用：tool、model、framework、language、api、product、project、acronym。无法识别的分类会按 project 保存。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 350))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 520),
            scrollView.heightAnchor.constraint(equalToConstant: 320),
            hint.widthAnchor.constraint(equalToConstant: 520),
        ])
        return container
    }

    private func loadTerms() {
        let text = DeveloperLexiconStore.load()
            .sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
            .map { term in
                "\(term.canonical) | \(term.category.rawValue) | \(term.aliases.joined(separator: ", "))"
            }
            .joined(separator: "\n")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func parseTerms(from text: String) -> [DeveloperTerm] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let canonical = parts.first, !canonical.isEmpty else { return nil }
            let category = parts.count > 1
                ? DeveloperTermCategory(rawValue: parts[1]) ?? .project
                : .project
            let aliases = parts.count > 2
                ? parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                : []
            return DeveloperTerm(canonical: canonical, aliases: aliases, category: category)
        }
    }
}
