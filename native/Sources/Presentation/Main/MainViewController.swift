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

    let contentWidth: CGFloat = 920
    let contentHeight: CGFloat = 560
    let leftColumnWidth: CGFloat = 200
    let leftTopInset: CGFloat = 28
    let rightTopInset: CGFloat = 18
    let recentViewportHeight: CGFloat = 190
    let brandIconVisibleSize: CGFloat = 48
    let maxRecentTranscriptions = 20

    let status = label("等待录音", size: 15, weight: .semibold)
    let detail = label("Fn 录音", size: 12)
    let micStatus = label("检测中", size: 12, weight: .medium)
    let accessibilityStatus = label("检测中", size: 12, weight: .medium)
    let screenRecordingStatus = label("检测中", size: 12, weight: .medium)
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
    let screenshotHotkeyValue = label(
        HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding).screenshotDisplayName,
        size: 13,
        weight: .medium
    )
    let secondaryScreenshotHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey)?.screenshotDisplayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let screenshotTranslationHotkeyValue = label(
        HotkeyBinding.load(
            storageKey: HotkeyBinding.screenshotTranslationStorageKey,
            fallback: .screenshotTranslationDefaultBinding
        ).screenshotDisplayName,
        size: 13,
        weight: .medium
    )
    let autoTranslateHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey)?.actionDisplayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let mainWindowHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)?.actionDisplayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let hotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let hotkeyResetButton = NSButton(title: "恢复 Fn", target: nil, action: nil)
    let secondaryHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let secondaryHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let screenshotHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let screenshotHotkeyResetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let secondaryScreenshotHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let secondaryScreenshotHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let screenshotTranslationHotkeyCaptureButton = NSButton(title: "Option + T", target: nil, action: nil)
    let screenshotTranslationHotkeyResetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let autoTranslateHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let autoTranslateHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let mainWindowHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let mainWindowHotkeyResetButton = NSButton(title: "清空", target: nil, action: nil)
    let modelValue = label("正在检查模型", size: 12, weight: .medium)
    let modelProgress = NSProgressIndicator()
    let modelInstallButton = NSButton(title: "安装模型", target: nil, action: nil)
    let realtime = BrandSwitch()
    let autoFinish = BrandSwitch()
    let duckSystemAudio = BrandSwitch()
    let launchAtLogin = BrandSwitch()
    let asrBackendMode = NSPopUpButton()
    let smartRewriteMode = NSPopUpButton()
    let deepSeekKeyButton = NSButton(title: "Key", target: nil, action: nil)
    let deepSeekBalanceButton = NSButton(title: "!", target: nil, action: nil)
    let promptSettingsButton = NSButton(title: "提示词", target: nil, action: nil)
    let autoScopeButton = NSButton(title: "范围", target: nil, action: nil)
    let developerTermsButton = NSButton(title: "术语", target: nil, action: nil)
    let autoTranslate = BrandSwitch()
    let translationDirectionMode = NSPopUpButton()
    let translationPromptButton = NSButton(title: "提示词", target: nil, action: nil)
    let screenshotSaveLocationButton = NSButton(title: "下载", target: nil, action: nil)
    let realtimeDraft = label("等待实时文本", size: 12)
    let realtimeTextView = NSTextView()
    let realtimeScroll = NSScrollView()
    let memoryLabel = label("内存 -- MB", size: 11, weight: .medium)
    var lastMemoryLevel: MemoryMonitor.Level = .normal
    var onInstallModel: (() -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding?) -> Void)?
    var preferencesViewController: NSViewController?

    let modelEntryName = label("SenseVoice int8", size: 13, weight: .semibold)
    let modelEntryStatus = label("检查中", size: 11, weight: .medium)
    let modelEntryDot = NSView()
    let modelPathLabel = label("", size: 11)
    let statusDot = NSView()
    let waveform = MiniWaveformView()
    let processingProgress = NSProgressIndicator()

    let recentStack = FlippedStackView()
    let recentScroll = NSScrollView()
    var recentRecords: [RecentTranscription] = []
    var isCapturingHotkey = false
    var capturingChannel: SpeechInputChannel?
    var capturingHotkeySlot: HotkeySlot?
    var hotkeyCaptureMonitor: Any?
    var hotkeyCaptureTap: CFMachPort?
    var hotkeyCaptureSource: CFRunLoopSource?
    var captureModifierKeyCodes: Set<Int> = []
    var captureConfirmWorkItem: DispatchWorkItem?
    var usageGuidePopover: NSPopover?
    var versionHistoryPopover: NSPopover?
    var testLogsPopover: NSPopover?
    var preferencesPopover: NSPopover?
    var modelDetailPopover: NSPopover?
    var deepSeekBalancePopover: NSPopover?
    let deepSeekBalanceClient = DeepSeekBalanceClient()
    lazy var versionHistoryViewController = VersionHistoryViewController()
    lazy var testLogsViewController = TestLogsViewController()

    enum HotkeySlot {
        case primary
        case secondary
        case screenshot
        case screenshotSecondary
        case screenshotTranslation
        case autoTranslate
        case mainWindow
    }

    enum MediaKeyCapture {
        static let systemDefinedEventType = CGEventType(rawValue: 14)!
        static let auxControlButtonSubtype = 8
        static let play = 16
        static let keyDownState = 0x0A
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
        configureASRBackendMenu(settings.asrBackend)
        asrBackendMode.target = self; asrBackendMode.action = #selector(saveSettings)
        configureSmartRewriteModeMenu(settings.smartRewritePreference)
        smartRewriteMode.target = self; smartRewriteMode.action = #selector(saveSettings)
        configureDeepSeekKeyButton()
        configurePromptSettingsButton()
        configureAutoScopeButton()
        configureDeveloperTermsButton()
        autoTranslate.state = settings.autoTranslateEnabled ? .on : .off
        autoTranslate.target = self; autoTranslate.action = #selector(saveSettings)
        configureTranslationDirectionMenu(settings.translationDirection)
        configureTranslationPromptButton()
        translationDirectionMode.target = self; translationDirectionMode.action = #selector(saveSettings)
        configureScreenshotSaveLocationButton()
        refreshLaunchAtLoginState()
        launchAtLogin.target = self; launchAtLogin.action = #selector(toggleLaunchAtLogin)
        configureOptionAccessibility()

        let left = buildLeftColumn()
        let center = buildCenterColumn()
        view.addSubview(left)
        view.addSubview(center)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.topAnchor.constraint(equalTo: view.topAnchor),
            left.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftColumnWidth),
            center.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 16),
            center.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            center.topAnchor.constraint(equalTo: view.topAnchor, constant: rightTopInset),
            center.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])

        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey),
            screenshot: HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding),
            secondaryScreenshot: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey),
            screenshotTranslation: HotkeyBinding.load(
                storageKey: HotkeyBinding.screenshotTranslationStorageKey,
                fallback: .screenshotTranslationDefaultBinding
            ),
            autoTranslate: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey),
            mainWindow: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
        )
        DispatchQueue.main.async { [weak self] in
            _ = self?.versionHistoryViewController.view
        }
    }

    func configureOptionAccessibility() {
        smartRewriteMode.setAccessibilityLabel("智能整理")
        asrBackendMode.setAccessibilityLabel("识别模型")
        asrBackendMode.toolTip = "选择 final 识别使用的本地 ASR 后端"
        deepSeekKeyButton.setAccessibilityLabel("DeepSeek API Key")
        promptSettingsButton.setAccessibilityLabel("智能整理提示词")
        autoScopeButton.setAccessibilityLabel("智能整理自动范围")
        developerTermsButton.setAccessibilityLabel("开发术语词库")
        autoTranslate.setAccessibilityLabel("自动翻译")
        autoTranslate.toolTip = "可在快捷键设置中配置快速打开或关闭"
        translationDirectionMode.setAccessibilityLabel("翻译方向")
        translationPromptButton.setAccessibilityLabel("翻译提示词")
        screenshotSaveLocationButton.setAccessibilityLabel("截图保存位置")
        realtime.setAccessibilityLabel("胶囊实时预览")
        autoFinish.setAccessibilityLabel("停顿自动完成")
        duckSystemAudio.setAccessibilityLabel("录音时降低电脑声音")
        launchAtLogin.setAccessibilityLabel("开机自动启动")
    }

    func configureSmartRewriteModeMenu(_ preference: SmartRewritePreference) {
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

    func configureASRBackendMenu(_ backend: ASRBackend) {
        asrBackendMode.removeAllItems()
        for item in ASRBackend.allCases {
            asrBackendMode.addItem(withTitle: item.displayName)
            asrBackendMode.lastItem?.tag = item.menuTag
        }
        asrBackendMode.selectItem(withTag: backend.menuTag)
        asrBackendMode.toolTip = "自动模式优先使用已安装的 Qwen3-ASR，否则回退 SenseVoice"
        asrBackendMode.bezelStyle = .rounded
        asrBackendMode.controlSize = .regular
        asrBackendMode.font = .systemFont(ofSize: 12)
    }

    func configureDeepSeekKeyButton() {
        deepSeekKeyButton.target = self
        deepSeekKeyButton.action = #selector(configureDeepSeekAPIKey)
        deepSeekKeyButton.bezelStyle = .rounded
        deepSeekKeyButton.controlSize = .regular
        deepSeekKeyButton.font = .systemFont(ofSize: 12, weight: .medium)
        deepSeekKeyButton.toolTip = "录入 DeepSeek API Key，保存到 macOS Keychain"
        deepSeekBalanceButton.target = self
        deepSeekBalanceButton.action = #selector(showDeepSeekBalance)
        deepSeekBalanceButton.bezelStyle = .circular
        deepSeekBalanceButton.controlSize = .small
        deepSeekBalanceButton.font = .systemFont(ofSize: 12, weight: .bold)
        deepSeekBalanceButton.toolTip = "查看 DeepSeek 实时余额和 TypeWhale 本机估算消费"
        refreshDeepSeekKeyButton()
    }

    func configurePromptSettingsButton() {
        promptSettingsButton.target = self
        promptSettingsButton.action = #selector(configureSmartRewritePrompts)
        promptSettingsButton.bezelStyle = .rounded
        promptSettingsButton.controlSize = .regular
        promptSettingsButton.font = .systemFont(ofSize: 12, weight: .medium)
        promptSettingsButton.toolTip = "调整、修改并保存智能整理提示词"
    }

    func configureAutoScopeButton() {
        autoScopeButton.target = self
        autoScopeButton.action = #selector(configureSmartRewriteAutoRules)
        autoScopeButton.bezelStyle = .rounded
        autoScopeButton.controlSize = .regular
        autoScopeButton.font = .systemFont(ofSize: 12, weight: .medium)
        autoScopeButton.toolTip = "设置自动模式在不同窗口中使用的整理模式"
    }

    func configureDeveloperTermsButton() {
        developerTermsButton.target = self
        developerTermsButton.action = #selector(configureDeveloperTerms)
        developerTermsButton.bezelStyle = .rounded
        developerTermsButton.controlSize = .regular
        developerTermsButton.font = .systemFont(ofSize: 12, weight: .medium)
        developerTermsButton.toolTip = "管理开发术语和别名"
    }

    func configureTranslationPromptButton() {
        translationPromptButton.target = self
        translationPromptButton.action = #selector(configureTranslationPrompts)
        translationPromptButton.bezelStyle = .rounded
        translationPromptButton.controlSize = .regular
        translationPromptButton.font = .systemFont(ofSize: 12, weight: .medium)
        translationPromptButton.toolTip = "调整、修改并保存自动翻译提示词"
    }

    func configureScreenshotSaveLocationButton() {
        screenshotSaveLocationButton.target = self
        screenshotSaveLocationButton.action = #selector(configureScreenshotSaveLocation)
        screenshotSaveLocationButton.bezelStyle = .rounded
        screenshotSaveLocationButton.controlSize = .regular
        screenshotSaveLocationButton.font = .systemFont(ofSize: 12, weight: .medium)
        refreshScreenshotSaveLocationButton()
    }

    func refreshScreenshotSaveLocationButton() {
        screenshotSaveLocationButton.title = ScreenshotSaveLocationStore.displayName
        screenshotSaveLocationButton.toolTip = "当前保存到：\(ScreenshotSaveLocationStore.directory.path)"
    }

    func refreshDeepSeekKeyButton() {
        let hasKey = DeepSeekAPIKeyStore.hasAPIKey()
        deepSeekKeyButton.title = "Key"
        deepSeekKeyButton.contentTintColor = hasKey ? UITheme.brandYellow : .secondaryLabelColor
        deepSeekKeyButton.toolTip = hasKey
            ? "DeepSeek API Key 已录入，点击可覆盖或清除"
            : "DeepSeek API Key 未录入，点击设置"
        deepSeekKeyButton.attributedTitle = NSAttributedString(
            string: "Key",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: hasKey ? .semibold : .medium),
                .foregroundColor: hasKey ? UITheme.brandYellow : NSColor.secondaryLabelColor,
            ]
        )
    }

    func toggleAutoTranslateFromShortcut() {
        autoTranslate.state = autoTranslate.state == .on ? .off : .on
        autoTranslate.needsDisplay = true
        saveSettings()
        let stateText = autoTranslate.state == .on ? "已开启" : "已关闭"
        detail.stringValue = "自动翻译\(stateText) · Shift + \\"
    }

    func configureTranslationDirectionMenu(_ direction: SmartTranslationDirection) {
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

    func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.42"
        let build = info?["CFBundleVersion"] as? String ?? "199"
        return "Version \(version) (\(build))"
    }

    func loadBrandIcon() -> NSImage? {
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

    func loadAppIcon() -> NSImage? {
        if let image = NSImage(named: "TypeWhale") {
            return image
        }
        if let url = Bundle.main.url(forResource: "TypeWhale", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    @objc func showUsageGuide(_ sender: NSButton) {
        if let popover = usageGuidePopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = usageGuidePopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 184)
        popover.contentViewController = makeUsageGuideController()
        usageGuidePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    func makeUsageGuideController() -> NSViewController {
        let title = label("使用方法", size: 14, weight: .semibold)
        let body = label(
            """
            先开启麦克风和辅助功能。
            按 Fn 开始录音，再按一次或松开结束。
            首次打开测试版：右键 App 选“打开”；若被拦截，到 系统设置 > 隐私与安全性，点“仍要打开”。
            """,
            size: 12
        )
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 0

        let stack = NSStackView(views: [title, hairlineView(), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 184))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])

        let controller = NSViewController()
        controller.view = content
        return controller
    }

    @objc func showVersionHistory(_ sender: NSButton) {
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

    @objc func showTestLogs(_ sender: NSButton) {
        if let popover = testLogsPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        testLogsViewController.reload()
        let popover = testLogsPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 430)
        popover.contentViewController = testLogsViewController
        testLogsPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc func showPreferencesPopover(_ sender: NSButton) {
        showPreferencesPopover(relativeTo: sender.bounds, of: sender)
    }

    func showPreferencesPopoverFromMenu() {
        let anchor = NSRect(x: 0, y: max(0, view.bounds.height - 44), width: leftColumnWidth, height: 36)
        showPreferencesPopover(relativeTo: anchor, of: view)
    }

    func showPreferencesPopover(relativeTo rect: NSRect, of anchorView: NSView) {
        if let popover = preferencesPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = preferencesPopover ?? NSPopover()
        // 半瞬态：在偏好里录快捷键、编辑提示词/术语会弹出 NSAlert，transient 会被焦点切换误关；
        // semitransient 只在点主窗口内容时关闭，编辑期间不会整块消失。
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentSize = NSSize(width: 540, height: 400)
        popover.contentViewController = makePreferencesViewController()
        preferencesPopover = popover
        popover.show(relativeTo: rect, of: anchorView, preferredEdge: .maxX)
    }

    @objc func showModelDetail(_ sender: NSGestureRecognizer) {
        guard let anchor = sender.view else { return }
        if let popover = modelDetailPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = modelDetailPopover ?? NSPopover()
        if modelDetailPopover == nil {
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 300, height: 282)
            popover.contentViewController = makeModelDetailController()
            modelDetailPopover = popover
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    func makeModelDetailController() -> NSViewController {
        let icon = symbolIcon("cpu", size: 18, color: UITheme.brandYellow)
        let title = label("本地 ASR 模型", size: 14, weight: .semibold)
        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping

        let backendCaption = label("识别模型", size: 11, weight: .medium)
        backendCaption.textColor = UITheme.sectionTitle
        asrBackendMode.setContentHuggingPriority(.required, for: .horizontal)
        asrBackendMode.widthAnchor.constraint(equalToConstant: 154).isActive = true
        let backendRow = NSStackView(views: [backendCaption, flexSpacer(), asrBackendMode])
        backendRow.orientation = .horizontal
        backendRow.alignment = .centerY
        backendRow.spacing = 10

        let desc = label("本地离线语音识别模型，全程在本机推理，不上传音频。Qwen3-ASR 使用原生 sherpa-onnx 链路。", size: 12)
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

        let stack = NSStackView(views: [titleRow, hairlineView(), backendRow, modelValue, modelProgress, desc, pathCaption, modelPathLabel, installRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 282))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 268),
            modelValue.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backendRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelPathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            installRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let controller = NSViewController()
        controller.view = content
        return controller
    }

    @objc func saveSettings() {
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
            asrBackend: asrBackend,
            smartRewritePreference: smartRewritePreference,
            autoTranslateEnabled: autoTranslate.state == .on,
            translationDirection: translationDirection
        ))
        refreshDisplayedModelState()
    }

    @objc func configureSmartRewritePrompts() {
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

    @objc func configureSmartRewriteAutoRules() {
        let dialog = SmartRewriteAutoRuleDialog(configuration: SmartRewriteAutoRuleStore.load())
        switch dialog.runModal() {
        case .save(let configuration):
            SmartRewriteAutoRuleStore.save(configuration)
            detail.stringValue = "智能整理自动范围已保存"
        case .reset:
            SmartRewriteAutoRuleStore.reset()
            detail.stringValue = "智能整理自动范围已恢复默认"
        case .cancel:
            break
        }
    }

    @objc func configureTranslationPrompts() {
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

    @objc func configureDeveloperTerms() {
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

    @objc func configureScreenshotSaveLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择截图保存位置"
        panel.message = "截图会直接保存到这个文件夹；如果位置不可用，会自动回到下载文件夹。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ScreenshotSaveLocationStore.directory

        guard panel.runModal() == .OK, let url = panel.url else {
            refreshScreenshotSaveLocationButton()
            return
        }
        ScreenshotSaveLocationStore.save(url)
        refreshScreenshotSaveLocationButton()
        detail.stringValue = "截图保存位置已更新：\(ScreenshotSaveLocationStore.displayName)"
    }

    @objc func configureDeepSeekAPIKey() {
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

    func showDeepSeekKeyError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "DeepSeek Key 保存失败"
        alert.runModal()
    }

    @objc func showDeepSeekBalance(_ sender: NSButton) {
        if let popover = deepSeekBalancePopover, popover.isShown {
            popover.close()
            return
        }

        let content = DeepSeekBalancePopoverViewController()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 268)
        popover.contentViewController = content
        deepSeekBalancePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)

        content.showLoading()
        Task { [weak self, weak content] in
            guard let self else { return }
            do {
                let balance = try await self.deepSeekBalanceClient.fetch()
                let localSpent = SmartUsageLedgerStore.totalEstimatedCostCNY
                await MainActor.run {
                    content?.show(balance: balance, localSpentCNY: localSpent)
                }
            } catch {
                await MainActor.run {
                    content?.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func toggleLaunchAtLogin() {
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

    func refreshLaunchAtLoginState() {
        launchAtLogin.isEnabled = true
        launchAtLogin.state = (LoginItemManager.isEnabled || LoginItemManager.isPendingApproval) ? .on : .off
        launchAtLogin.needsDisplay = true
        launchAtLogin.toolTip = LoginItemManager.isPendingApproval
            ? "已提交开机启动请求，请在系统设置的登录项中允许 TypeWhale"
            : "登录 macOS 后自动启动 TypeWhale"
    }

    @objc func installModel() {
        onInstallModel?()
    }

    func updateModelState(_ state: SenseVoiceModelInstaller.State) {
        refreshDisplayedModelState(installerState: state)
    }

    func refreshDisplayedModelState(installerState state: SenseVoiceModelInstaller.State? = nil) {
        let selectedBackend = asrBackend.resolvedBackend
        modelEntryName.stringValue = asrBackend == .automatic
            ? "\(selectedBackend.displayName) · 自动"
            : selectedBackend.displayName
        if selectedBackend == .qwen3ASR {
            if let qwenPath = Qwen3ASRModelManifest.preferredModelDirectory?.path {
                modelEntryStatus.stringValue = "已就绪"
                modelEntryStatus.textColor = .systemGreen
                modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                modelValue.toolTip = qwenPath
                modelValue.stringValue = "Qwen3-ASR 原生模型已就绪，可离线识别"
                modelValue.textColor = .systemGreen
                modelPathLabel.stringValue = qwenPath
                modelProgress.isHidden = true
                modelInstallButton.isHidden = true
                return
            }
            modelEntryStatus.stringValue = "未安装"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = Qwen3ASRModelManifest.modelDirectory.path
            modelValue.stringValue = "Qwen3-ASR 模型缺失，自动模式会回退 SenseVoice"
            modelValue.textColor = .systemOrange
            modelPathLabel.stringValue = Qwen3ASRModelManifest.modelDirectory.path
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
            return
        }

        let state = state ?? (SenseVoiceModelManifest.preferredModelDirectory == nil ? .missing : .ready)
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
            modelEntryName.stringValue = asrBackend == .automatic ? "SenseVoice int8 · 自动" : "SenseVoice int8"
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

    func statusColor(for tone: PrimaryStatusTone) -> NSColor {
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

    @objc func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openScreenRecording() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func openKeyboard() {
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

    var asrBackend: ASRBackend {
        ASRBackend.fromMenuTag(asrBackendMode.selectedItem?.tag ?? 0)
    }

    var smartRewritePreference: SmartRewritePreference {
        SmartRewritePreference.fromMenuTag(smartRewriteMode.selectedItem?.tag ?? 0)
    }

    /// 循环切换到下一个整理模式，持久化并返回新模式（供胶囊手动切换调用）。
    @discardableResult
    func cycleSmartRewritePreference() -> SmartRewritePreference {
        let all = SmartRewritePreference.allCases
        let index = all.firstIndex(of: smartRewritePreference) ?? 0
        let next = all[(index + 1) % all.count]
        smartRewriteMode.selectItem(withTag: next.menuTag)
        saveSettings()
        return next
    }

    var autoTranslateEnabled: Bool {
        autoTranslate.state == .on
    }

    var translationDirection: SmartTranslationDirection {
        SmartTranslationDirection.fromMenuTag(translationDirectionMode.selectedItem?.tag ?? 0)
    }

}
