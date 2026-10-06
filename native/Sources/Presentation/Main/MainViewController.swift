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
    static let windowContentSize = NSSize(width: 1000, height: 620)
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
    let ideaPillHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.ideaPillStorageKey)?.actionDisplayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let openClawHotkeyValue = label(
        HotkeyBinding.loadOpenClaw()?.actionDisplayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let hotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let hotkeyResetButton = NSButton(title: "恢复 Fn", target: nil, action: nil)
    let hotkeyMouseShortcutPicker = NSPopUpButton()
    let secondaryHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let secondaryHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let secondaryHotkeyMouseShortcutPicker = NSPopUpButton()
    let screenshotHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let screenshotHotkeyResetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let screenshotHotkeyMouseShortcutPicker = NSPopUpButton()
    let secondaryScreenshotHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let secondaryScreenshotHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let secondaryScreenshotHotkeyMouseShortcutPicker = NSPopUpButton()
    let screenshotTranslationHotkeyCaptureButton = NSButton(title: "Option + T", target: nil, action: nil)
    let screenshotTranslationHotkeyResetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let screenshotTranslationHotkeyMouseShortcutPicker = NSPopUpButton()
    let autoTranslateHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let autoTranslateHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let autoTranslateHotkeyMouseShortcutPicker = NSPopUpButton()
    let mainWindowHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let mainWindowHotkeyResetButton = NSButton(title: "清空", target: nil, action: nil)
    let mainWindowHotkeyMouseShortcutPicker = NSPopUpButton()
    let ideaPillHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let ideaPillHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let ideaPillHotkeyMouseShortcutPicker = NSPopUpButton()
    let openClawHotkeyCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let openClawHotkeyResetButton = NSButton(title: "清空", target: nil, action: nil)
    let openClawHotkeyMouseShortcutPicker = NSPopUpButton()
    let openClawHotkeyPanelCaptureButton = NSButton(title: "未设置", target: nil, action: nil)
    let openClawHotkeyPanelResetButton = NSButton(title: "清空", target: nil, action: nil)
    let openClawHotkeyPanelMouseShortcutPicker = NSPopUpButton()
    let openClawGatewayField = NSTextField(string: OpenClawSettingsStore.load().gatewayURL)
    let openClawAgentField = NSTextField(string: OpenClawSettingsStore.load().agentID)
    let openClawSessionField = NSTextField(string: OpenClawSettingsStore.load().sessionKey)
    let openClawCLIPathField = NSTextField(string: OpenClawSettingsStore.load().cliPath)
    let openClawStatusValue = label("未检测", size: 12, weight: .medium)
    let openClawCheckButton = NSButton(title: "检测连接", target: nil, action: nil)
    let openClawVoiceEnabledSwitch = BrandSwitch()
    let openClawVoiceVolumeSlider = NSSlider(
        value: OpenClawVoiceSettings.default.volume,
        minValue: OpenClawVoiceSettings.minimumVolume,
        maxValue: OpenClawVoiceSettings.maximumVolume,
        target: nil,
        action: nil
    )
    let openClawVoiceVolumeValue = label("80%", size: 12, weight: .medium)
    let openClawVoiceRateSlider = NSSlider(
        value: OpenClawVoiceSettings.default.speechRate,
        minValue: OpenClawVoiceSettings.minimumSpeechRate,
        maxValue: OpenClawVoiceSettings.maximumSpeechRate,
        target: nil,
        action: nil
    )
    let openClawVoiceRateValue = label("1.25x", size: 12, weight: .medium)
    let openClawVoiceMode = NSPopUpButton()
    let openClawVoicePlaybackMode = NSPopUpButton()
    let openClawVoiceInterruptMode = NSPopUpButton()
    let ttsReadingLabView = TTSReadingLabView()
    let ttsReadingLabSettings = TTSReadingLabSettingsStore()
    let ttsReadingLabResultStore = TTSLabResultStore()
    lazy var ttsReadingLabService = TTSReadingLabService()
    let ttsPersonalVoiceStore = TTSLabPersonalVoiceStore()
    var ttsMyVoiceRecordingController: TTSMyVoiceRecordingViewController?
    var ttsReadingLabModels: [TTSLabModel] = []
    var ttsReadingLabActiveModel: TTSLabModel?
    var ttsReadingLabActiveVoice: TTSLabVoice?
    var ttsReadingLabActiveText = ""
    var ttsReadingLabConfigured = false
    var ttsReadingLabIsRunning = false
    let modelValue = label("正在检查模型", size: 12, weight: .medium)
    let modelProgress = NSProgressIndicator()
    let modelInstallButton = NSButton(title: "安装模型", target: nil, action: nil)
    let realtime = BrandSwitch()
    let shadowPreviewExperiment = BrandSwitch()
    let onlineASRProviderMode = NSPopUpButton()
    let doubaoASRKeyButton = NSButton(title: "未配置", target: nil, action: nil)
    let mimoASRKeyButton = NSButton(title: "未配置", target: nil, action: nil)
    let onlineASRPrivacyNote = NSTextField(wrappingLabelWithString: "在线音频仅在选择对应服务并开始下一轮录音后发送；不参与最终识别和粘贴。")
    let correctedPreviewExperiment = BrandSwitch()
    let longFormIncrementalOutputExperiment = BrandSwitch()
    weak var previewThemeClassicTile: ThemePreviewTile?
    weak var previewThemeNotchTile: ThemePreviewTile?
    weak var previewThemeMinimalBlackTile: ThemePreviewTile?
    var selectedPreviewTheme: PreviewTheme = .default
    let autoFinish = BrandSwitch()
    let duckSystemAudio = BrandSwitch()
    let pauseSystemMedia = BrandSwitch()
    let reRecognizeWholeRecordingAfterStop = BrandSwitch()
    let audioInputDeviceMode = NSPopUpButton()
    let audioInputRefreshButton = NSButton(title: "", target: nil, action: nil)
    let preferBuiltInMicForBluetoothAudio = BrandSwitch()
    let audioInputStatus = label(
        AudioInputDevice.selectedName.isEmpty ? "按需读取可用设备" : "主麦克风：\(AudioInputDevice.selectedName)",
        size: 11,
        weight: .medium
    )
    let launchAtLogin = BrandSwitch()
    let asrBackendMode = ASRBackendSegmentedSelector()
    let asrSwitchProgress = NSProgressIndicator()
    let asrSwitchProgressLabel = label("", size: 11, weight: .medium)
    let asrBenchmarkButton = NSButton(title: "ASR 模型测速", target: nil, action: nil)
    let smartRewriteMode = NSPopUpButton()
    let ideaPillRewriteMode = NSPopUpButton()
    let smartAIModelMode = NSPopUpButton()
    let modelTabSmartAIModelMode = NSPopUpButton()
    let localModelHealthCheckButton = NSButton(title: "开始检测", target: nil, action: nil)
    let localModelHealthCopyButton = NSButton(title: "复制诊断", target: nil, action: nil)
    let localModelHealthStatusLabel = label("尚未检测", size: 12, weight: .semibold)
    let localModelHealthDetailLabel = NSTextField(
        wrappingLabelWithString: "点击后将实际加载模型并完成一次最小生成"
    )
    lazy var localModelHealthCheckService = ManagedLLMRuntimeService.shared
        .makeLocalModelHealthCheckService()
    var localModelHealthCheckTask: Task<Void, Never>?
    var localModelHealthDiagnosticText: String?
    let deepSeekKeyButton = NSButton(title: "Key", target: nil, action: nil)
    let deepSeekBalanceButton = NSButton(title: "!", target: nil, action: nil)
    let promptSettingsButton = NSButton(title: "提示词", target: nil, action: nil)
    let autoScopeButton = NSButton(title: "范围", target: nil, action: nil)
    let autoSendAfterPaste = BrandSwitch()
    let autoSendCountdownSeconds = NSStepper()
    let autoSendCountdownValueLabel = NSTextField(labelWithString: "2 秒")
    lazy var autoSendCountdownControl: NSStackView = {
        let stack = NSStackView(views: [
            autoSendCountdownValueLabel,
            autoSendCountdownSeconds,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }()
    let autoSendApplicationScopeButton = NSButton(
        title: "应用范围",
        target: nil,
        action: nil
    )
    let developerTermsButton = NSButton(title: "术语", target: nil, action: nil)
    let autoTranslate = BrandSwitch()
    let translationDirectionMode = NSPopUpButton()
    let translationPromptButton = NSButton(title: "提示词", target: nil, action: nil)
    let socialScopeButton = NSButton(title: "社交清单", target: nil, action: nil)
    let screenshotSaveLocationButton = NSButton(title: "下载", target: nil, action: nil)
    let screenshotArchiveMode = NSPopUpButton()
    let backlogDirectoryButton = NSButton(title: "需求池", target: nil, action: nil)
    let replayLaunchAnimationButton = NSButton(title: "重播启动动画", target: nil, action: nil)
    let realtimeDraft = label("等待实时文本", size: 12)
    let realtimeTextView = NSTextView()
    let realtimeScroll = NSScrollView()
    let memoryLabel = label("内存 -- MB", size: 11, weight: .medium)
    var lastMemoryLevel: MemoryMonitor.Level = .normal
    var onInstallModel: (() -> Void)?
    var onASRBackendChange: ((ASRBackend, @escaping (Result<Void, Error>) -> Void) -> Void)?
    var onShowASRBenchmark: (() -> Void)?
    var onRequestFullAppExit: (() -> Void)?
    var onSmartAIModelChange: ((SmartAIModel) -> Void)?
    let scheduledASRBackendChangeDelay: TimeInterval = 3.5
    var pendingASRBackendChangeWorkItem: DispatchWorkItem?
    var asrSwitchProgressTimer: Timer?
    var asrSwitchGeneration = UUID()
    var asrSwitchTarget: ASRBackend?
    var activeASRBackend: ASRBackend = .senseVoice
    var funASRRuntimeInstallerState: FunASRRuntimeInstaller.State = .missing
    var onPrimaryMicrophoneSelection: ((String) -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding, HotkeyBinding?, HotkeyBinding?, HotkeyBinding?, HotkeyBinding?) -> Void)?
    var onRemoteEnabledChange: ((Bool) -> Void)?
    var onRemotePrimaryAction: (() -> Void)?
    var onRemoteMappingChange: ((RemoteButton, RemoteButtonAction) -> Void)?
    var onRemoteResetMappings: (() -> Void)?
    lazy var managedASRModelDownloader = ManagedASRModelDownloader()
    var smartAIModelSelectionGeneration = UUID()
    lazy var liveASRModelRegistry = ASRModelRegistry(environment: .init(
        bundledModelsURL: AppPaths.resources.appendingPathComponent("Models", isDirectory: true),
        managedModelsURL: AppPaths.models,
        legacyModelsURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeWhale/Models", isDirectory: true),
        huggingFaceHubURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
        modelScopeHubURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/modelscope/hub/models", isDirectory: true),
        admissionEvidenceURL: AppPaths.resources.appendingPathComponent("local-candidate-admission.json")
    ))
    lazy var managedASRModelListView = ManagedASRModelListView(
        downloader: managedASRModelDownloader,
        onMessage: { [weak self] message in
            self?.detail.stringValue = message
        }
    )

    let modelEntryName = label("SenseVoice int8", size: 13, weight: .semibold)
    let modelEntryStatus = label("检查中", size: 11, weight: .medium)
    let modelEntryDot = NSView()
    let modelPathLabel = label("", size: 11)
    let statusDot = NSView()
    let waveform = MiniWaveformView()
    let processingProgress = NSProgressIndicator()

    let recentStack = FlippedStackView()
    let recentScroll = NSScrollView()
    var selectedInspectorTab: MainInspectorTab = .common
    let inspectorTabControl = NSSegmentedControl(labels: MainInspectorTab.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    var didApplyInspectorControlSizing = false
    let inspectorContent = FlippedView()
    let inspectorScroll = NSScrollView()
    var latestRemoteInputSnapshot = RemoteInputSnapshot.initial
    weak var remoteInspectorView: RemoteInspectorView?
    var recentRecords: [RecentTranscription] = []
    var isCapturingHotkey = false
    var capturingChannel: SpeechInputChannel?
    var capturingHotkeySlot: HotkeySlot?
    weak var activeHotkeyCaptureButton: NSButton?
    var hotkeyCaptureMonitor: Any?
    var hotkeyCaptureTap: CFMachPort?
    var hotkeyCaptureSource: CFRunLoopSource?
    var captureModifierKeyCodes: Set<Int> = []
    var captureConfirmWorkItem: DispatchWorkItem?
    var usageGuidePopover: NSPopover?
    var versionHistoryPopover: NSPopover?
    var testLogsPopover: NSPopover?
    var mouseShortcutTestPopover: NSPopover?
    var modelDetailPopover: NSPopover?
    var deepSeekBalancePopover: NSPopover?
    var openClawConnectionCheckInFlight = false
    var mouseShortcutTestMonitor: Any?
    var audioInputRouteObserver: AudioInputRouteObserver?
    var audioInputDeviceMenuHasLoaded = false
    var smartAIKeyRow: NSView?
    var smartAIUsageRow: NSView?
    let deepSeekBalanceClient = DeepSeekBalanceClient()
    lazy var versionHistoryViewController = VersionHistoryViewController()
    lazy var testLogsViewController = TestLogsViewController()
    lazy var mouseShortcutTestViewController = MouseButtonTestViewController()

    enum HotkeySlot: Int {
        case primary
        case secondary
        case screenshot
        case screenshotSecondary
        case screenshotTranslation
        case autoTranslate
        case mainWindow
        case ideaPill
        case openClaw
    }

    enum MainInspectorTab: CaseIterable {
        case common
        case intelligence
        case models
        case openClaw
        case voice
        case remote
        case hotkeys

        var title: String {
            switch self {
            case .common: return "常用"
            case .intelligence: return "智能"
            case .models: return "模型"
            case .openClaw: return "OpenClaw"
            case .voice: return "声音"
            case .remote: return "遥控器"
            case .hotkeys: return "快捷键"
            }
        }
    }

    enum MediaKeyCapture {
        static let systemDefinedEventType = CGEventType(rawValue: 14)!
        static let auxControlButtonSubtype = 8
        static let play = 16
        static let keyDownState = 0x0A
    }

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        // 晨雾浅色：换成浅色 vibrancy + aqua 外观，系统控件（下拉/开关/滚动条）随之浅化。
        if AppSettingsStore.useMistLightTheme {
            root.material = .contentBackground
            root.appearance = NSAppearance(named: .aqua)
        } else {
            root.material = .hudWindow
            root.appearance = NSAppearance(named: .darkAqua)
        }
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
        darkOverlay.layer?.backgroundColor = UITheme.windowOverlay.cgColor
        view.addSubview(darkOverlay)
        NSLayoutConstraint.activate([
            darkOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            darkOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            darkOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            darkOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let settings = AppSettingsStore.loadMainViewSettings()
        let experimentalPreviewSettings = ExperimentalPreviewSettingsStore().load()
        realtime.state = settings.realtimePreviewEnabled ? .on : .off
        realtime.target = self; realtime.action = #selector(saveSettings)
        shadowPreviewExperiment.state = ShadowPreviewSettingsStore().load().isEnabled ? .on : .off
        shadowPreviewExperiment.target = self
        shadowPreviewExperiment.action = #selector(saveShadowPreviewSettings)
        configureOnlineASRControls(settings: OnlineASRSettingsStore().load())
        correctedPreviewExperiment.state = experimentalPreviewSettings.correctedPreviewEnabled ? .on : .off
        correctedPreviewExperiment.target = self
        correctedPreviewExperiment.action = #selector(saveExperimentalPreviewSettings)
        longFormIncrementalOutputExperiment.state = experimentalPreviewSettings.longFormIncrementalOutputEnabled ? .on : .off
        longFormIncrementalOutputExperiment.target = self
        longFormIncrementalOutputExperiment.action = #selector(saveExperimentalPreviewSettings)
        selectedPreviewTheme = settings.previewTheme
        autoFinish.state = settings.autoFinishAfterPauseEnabled ? .on : .off
        autoFinish.target = self; autoFinish.action = #selector(saveSettings)
        duckSystemAudio.state = settings.duckSystemAudioWhileRecordingEnabled ? .on : .off
        duckSystemAudio.target = self; duckSystemAudio.action = #selector(saveSettings)
        pauseSystemMedia.state = settings.pauseSystemMediaWhileRecordingEnabled ? .on : .off
        pauseSystemMedia.target = self; pauseSystemMedia.action = #selector(saveSettings)
        reRecognizeWholeRecordingAfterStop.state = settings.reRecognizeWholeRecordingAfterStop ? .on : .off
        reRecognizeWholeRecordingAfterStop.target = self; reRecognizeWholeRecordingAfterStop.action = #selector(saveSettings)
        configureAudioInputDeviceControls(selectedUID: settings.audioInputDeviceUID)
        audioInputDeviceMode.target = self; audioInputDeviceMode.action = #selector(selectPrimaryMicrophone)
        preferBuiltInMicForBluetoothAudio.state = settings.preferBuiltInMicForBluetoothAudio ? .on : .off
        preferBuiltInMicForBluetoothAudio.target = self; preferBuiltInMicForBluetoothAudio.action = #selector(saveSettings)
        activeASRBackend = settings.asrBackend
        configureASRBackendMenu(settings.asrBackend)
        asrBackendMode.target = self; asrBackendMode.action = #selector(saveSettings)
        configureSmartRewriteModeMenu(settings.smartRewritePreference)
        smartRewriteMode.target = self; smartRewriteMode.action = #selector(saveSettings)
        configureIdeaPillRewriteModeMenu(IdeaPillRewriteModeStore.load())
        ideaPillRewriteMode.target = self; ideaPillRewriteMode.action = #selector(saveSettings)
        ManagedLLMSelectionStore.shared.retireLegacySelection()
        configureSmartAIModelMenu(SmartAIModelStore.load())
        smartAIModelMode.target = self; smartAIModelMode.action = #selector(selectSmartAIModel)
        modelTabSmartAIModelMode.target = self; modelTabSmartAIModelMode.action = #selector(selectSmartAIModel)
        configureLocalModelHealthCheckControls()
        configureDeepSeekKeyButton()
        configurePromptSettingsButton()
        configureAutoScopeButton()
        configureAutoSendControls()
        configureDeveloperTermsButton()
        autoTranslate.state = settings.autoTranslateEnabled ? .on : .off
        autoTranslate.target = self; autoTranslate.action = #selector(saveSettings)
        configureTranslationDirectionMenu(settings.translationDirection)
        configureTranslationPromptButton()
        configureSocialScopeButton()
        translationDirectionMode.target = self; translationDirectionMode.action = #selector(saveSettings)
        configureScreenshotSaveLocationButton()
        configureScreenshotArchiveModeMenu(ScreenshotArchiveModeStore.load())
        screenshotArchiveMode.target = self; screenshotArchiveMode.action = #selector(saveSettings)
        configureBacklogDirectoryButton()
        configureReplayLaunchAnimationButton()
        refreshLaunchAtLoginState()
        launchAtLogin.target = self; launchAtLogin.action = #selector(toggleLaunchAtLogin)
        configureOptionAccessibility()
        normalizeExperimentalPreviewSettings(persist: true, restoreSavedPreference: true)

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
            mainWindow: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey),
            ideaPill: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.ideaPillStorageKey),
            openClaw: HotkeyBinding.loadOpenClaw()
        )
        DispatchQueue.main.async { [weak self] in
            _ = self?.versionHistoryViewController.view
        }
    }

    deinit {
        localModelHealthCheckTask?.cancel()
        audioInputRouteObserver?.stop()
    }
}
