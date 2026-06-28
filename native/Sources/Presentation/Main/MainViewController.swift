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

    /// 主窗口内容尺寸的唯一真值。窗口实际高度由本 VC 的必需约束决定，
    /// AppLifecycleCoordinator.windowSize 直接引用它，避免两处尺寸不一致。
    static let windowContentSize = NSSize(width: 1000, height: 580)
    let contentWidth: CGFloat = MainViewController.windowContentSize.width
    let contentHeight: CGFloat = MainViewController.windowContentSize.height
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
    var panelScrollView: NSScrollView?
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
    let backlogDirectoryButton = NSButton(title: "需求池", target: nil, action: nil)
    let realtimeDraft = label("等待实时文本", size: 12)
    let realtimeTextView = NSTextView()
    let realtimeScroll = NSScrollView()
    let memoryLabel = label("内存 -- MB", size: 11, weight: .medium)
    var lastMemoryLevel: MemoryMonitor.Level = .normal
    var onInstallModel: (() -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding?) -> Void)?

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
        configureBacklogDirectoryButton()
        refreshLaunchAtLoginState()
        launchAtLogin.target = self; launchAtLogin.action = #selector(toggleLaunchAtLogin)
        configureOptionAccessibility()

        let surface = buildMainSurface()
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

}
