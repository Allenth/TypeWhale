import AppKit
import CoreAudio
import Foundation

@MainActor
final class SpeechInputCoordinator {
    private enum Timing {
        static let autoFinishPauseSeconds: TimeInterval = 2.0
        static let initialSilenceAutoFinishSeconds: TimeInterval = 8.0
        /// 450ms keeps an intentional long press distinct from a normal tap, including Bluetooth HID jitter.
        static let holdToRecordNanoseconds: UInt64 = 450_000_000
        static let holdToRecordSeconds = TimeInterval(holdToRecordNanoseconds) / 1_000_000_000
        /// 单次录音硬上限：超过即自动结束并识别，封住异常长录音的能耗和内存峰值。
        /// 当前产品允许连续录制 5 分钟；分块预览和缓存负责限制长录音期间的识别开销。
        static let maxRecordingSeconds: TimeInterval = 300
        /// 录音中持续无语音/文字产出的上限：已说过话则自动收尾保存，从未说话则取消空录音。
        static let noTextTimeoutSeconds: TimeInterval = 300
        static let backgroundHealthSeconds: TimeInterval = 30
        static let recordingSafetySeconds: TimeInterval = 1
        static let capsuleStatusSeconds: TimeInterval = 1
        static let openClawHealthProbeSeconds: TimeInterval = 10
        static let memorySafetyCheckSeconds: TimeInterval = 30
        static let longFormDiskSafetyProbeSeconds: TimeInterval = 30
        static let wakeRecoveryGraceSeconds: TimeInterval = 3
        static let realtimeSnapshotTimeoutSeconds: TimeInterval = 3
        static let realtimeSilenceGateProbeFreshnessSeconds: TimeInterval = 1.2
        static let realtimeSilenceGateVoiceGraceSeconds: TimeInterval = 0.9
        static let startupHotkeyRecoveryDelays: [TimeInterval] = [0.5, 1.5, 3, 6, 10]
    }

    private struct CapsuleModePresentation {
        let modeName: String
        let emphasis: PreviewModeEmphasis
    }

    private typealias FinalDeliveryCandidateSnapshots = (
        shadow: CandidateDeliverySnapshot?,
        realtimePreviewDelivery: CandidateDeliverySnapshot?
    )

    private struct PendingRecordingStart {
        let instructions: String
        let activation: RecordingActivation
        let channel: SpeechInputChannel
        let purpose: SpeechInputPurpose
        let captureSource: SpeechCaptureSource
    }

    private struct PendingOpenClawMessage {
        let turnID: UUID
        let text: String
        let elapsed: Double
        let task: RecordingTask
        let settings: OpenClawSettings
    }

    private struct VoiceProbeRequest {
        let taskID: UUID
        let samples: [Float]
        let sampleRate: Int
        let capturedAt: Date
        let sequence: Int
    }

    private var recordingStartedAt: Date?
    /// 只管理“停止采集 → 完成任务级预览快照”的短交接；后续识别由 SpeechWorkflowState 管理。
    private var recordingStopHandoff = RecordingStopHandoff()
    private var pendingRecordingStart: PendingRecordingStart?
    private var lastCapsuleStatusUpdateAt: Date?
    private var lastVoiceAt: Date?
    private var voiceEverDetected = false
    /// 本轮人声检测（Silero）是否可用；Silero 探测出错时置 false → 停顿自动结束随之停用，
    /// 仅保留手动停止与硬上限，避免误判成"一直没人声"而过早结束。
    private var voiceDetectionAvailable = false
    private var voiceProbeInFlight = false
    private var voiceProbeSequence = 0
    private var latestVoiceProbeHasSpeech: Bool?
    private var latestVoiceProbeCapturedAt: Date?
    private var pendingVoiceProbes = BoundedVoiceProbeBacklog<VoiceProbeRequest>(capacity: 4)
    private var autoFinishPolicy = RecordingAutoFinishPolicy(
        pauseSeconds: Timing.autoFinishPauseSeconds,
        initialSilenceSeconds: Timing.initialSilenceAutoFinishSeconds
    )

    private let controller: MainViewController
    private let showMainWindow: () -> Void
    private let recorder = AudioRecorder()
    private lazy var remoteInputCoordinator = RemoteInputCoordinator(
        beginSpeech: { [weak self] sampleRate in
            self?.beginRemoteSpeech(sampleRate: sampleRate)
        },
        appendPCM: { [weak self] samples, taskID in
            self?.appendRemotePCM16(samples, taskID: taskID)
        },
        endSpeech: { [weak self] taskID in
            self?.endRemoteSpeech(taskID: taskID)
        },
        cancelSpeech: { [weak self] taskID in
            self?.cancelRemoteSpeech(taskID: taskID)
        },
        speechPipelineIsBusy: { [weak self] in
            self?.isSpeechPipelineBusy ?? false
        },
        showMainWindow: { [weak self] in
            self?.showMainWindow()
        },
        send: { [weak self] in
            self?.postPasteKeyEmitter.emit(.returnKey) ?? false
        },
        cancelCurrentOperation: { [weak self] in
            self?.cancelCurrentOperationFromRemote()
        }
    )
    private var popup: PreviewPresenting = RecordingPanel()
    private var activePreviewTheme: PreviewTheme = .classic
    private let hotkey = HotkeyMonitor()
    private let modelInstaller = SenseVoiceModelInstaller()
    private lazy var funASRRuntimeInstaller = FunASRRuntimeInstaller(
        runtimeRoot: AppPaths.runtimes.appendingPathComponent("funasr/\(FunASRRuntimeManifest.version)", isDirectory: true),
        requirementsURL: AppPaths.resources.appendingPathComponent("funasr_runtime_requirements.txt")
    )
    private let nativeASR = NativeSenseVoiceBridge(runtimeName: "shared")
    private let shadowASR = NativeSenseVoiceBridge(runtimeName: "shadow")
    /// 专用于 Silero VAD 的独立桥接：所有 VAD 调用（实时探测 + 末尾人声闸门）都走它自己的串行队列，
    /// 不再和慢速 SenseVoice 重识别抢同一条队列被饿死；全局 g_cached_vad 也因此只被一条队列访问，无竞争。
    private let vadBridge = NativeSenseVoiceBridge(runtimeName: "vad")
    private let outputAudioDucker = OutputAudioDucker()
    private let systemMediaPlaybackController = SystemMediaPlaybackController()
    private let smartEngine = SelectedSmartAITextEngine()
    private lazy var senseVoiceFinalASR = SenseVoiceRouter(runtimeName: "final", native: nativeASR)
    private lazy var localASRRegistry = ASRModelRegistry(environment: .init(
        bundledModelsURL: AppPaths.resources.appendingPathComponent("Models", isDirectory: true),
        managedModelsURL: AppPaths.models,
        legacyModelsURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeWhale/Models", isDirectory: true),
        huggingFaceHubURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
        modelScopeHubURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/modelscope/hub/models", isDirectory: true),
        admissionEvidenceURL: AppPaths.resources.appendingPathComponent("local-candidate-admission.json")
    ))
    private lazy var benchmarkFunASRSidecar = FunASRSidecar(
        pythonURL: AppPaths.runtimes.appendingPathComponent("funasr/\(FunASRRuntimeManifest.version)/python/bin/python3"),
        workerURL: AppPaths.resources.appendingPathComponent("funasr_asr_worker.py"),
        requestTimeout: 180
    )
    private lazy var benchmarkMLXSidecar = MLXASRSidecar(
        pythonURL: AppPaths.runtimes.appendingPathComponent("mlx-asr/\(MLXASRRuntimeManifest.version)/python/bin/python3"),
        workerURL: AppPaths.resources.appendingPathComponent("mlx_asr_worker.py"),
        requestTimeout: 240
    )
    private lazy var sherpaCandidateSidecar = SherpaASRSidecar(
        executableURL: AppPaths.resources.appendingPathComponent("TypeWhaleSherpaASR"),
        requestTimeout: 180
    )
    private lazy var unifiedLocalASR = UnifiedLocalASRAdapter(engines: [
        .sherpa: SherpaLocalEngineAdapter(sidecar: sherpaCandidateSidecar),
        .funASR: FunASRLocalEngineAdapter(sidecar: benchmarkFunASRSidecar),
        .mlx: MLXLocalEngineAdapter(sidecar: benchmarkMLXSidecar),
    ])
    private lazy var benchmarkRoot = AppPaths.caches.appendingPathComponent("ASRBenchmark", isDirectory: true)
    private lazy var benchmarkStore = ASRBenchmarkStore(rootURL: benchmarkRoot)
    private lazy var benchmarkCoordinator = ASRBenchmarkCoordinator(
        runner: unifiedLocalASR,
        persist: { [weak self] result in
            guard let self else { return }
            try self.benchmarkStore.save(result)
        }
    )
    private lazy var benchmarkWindowController: ASRBenchmarkWindowController = {
        let content = ASRBenchmarkViewController(
            coordinator: benchmarkCoordinator,
            descriptors: localASRRegistry.descriptors(),
            rootURL: benchmarkRoot
        )
        content.onClear = { [weak self] in try? self?.benchmarkStore.clear() }
        return ASRBenchmarkWindowController(content: content)
    }()
    private lazy var asr = ProviderAwareFinalASR(
        senseVoice: senseVoiceFinalASR,
        unified: unifiedLocalASR,
        descriptor: { [weak self] backend in self?.localASRRegistry.descriptor(for: backend.candidateID) },
        hotwords: {
            DeveloperLexiconStore.load().map(\.canonical)
        }
    )
    private lazy var realtimeASR = SenseVoiceRouter(runtimeName: "realtime", native: nativeASR)
    private lazy var finalRecognitionUseCase = FinalRecognitionUseCase(transcriber: asr)
    private lazy var finalDeliveryUseCase = FinalDeliveryUseCase(recognitionUseCase: finalRecognitionUseCase)
    private lazy var smartInputRouter = SmartInputRouter(engine: smartEngine)
    private lazy var screenshotCoordinator = ScreenshotCoordinator()
    private let postPasteKeyEmitter = SystemPostPasteKeyEmitter()
    private lazy var autoSendCountdownCoordinator =
        AutoSendCountdownCoordinator(
            presenter: AutoSendCountdownPresenter(
                capsuleFrame: { [weak self] in
                    self?.popup.presentationFrame
                }
            ),
            timerScheduler: MainRunLoopCountdownTimerScheduler(),
            durationSeconds: {
                AutoSendSettingsStore.load().countdownSeconds
            },
            now: { ProcessInfo.processInfo.systemUptime },
            frontmostPID: {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            },
            emit: { [weak self] action in
                self?.postPasteKeyEmitter.emit(action) ?? false
            },
            diagnostics: { LaunchDiagnostics.mark($0) }
        )
    private lazy var pasteCoordinator = PasteCoordinator(
        postPasteActionScheduler: autoSendCountdownCoordinator
    )
    private let autoSendPolicy = AutoSendPolicy()
    private var inputState: SpeechInputState = .idle
    private var workflowState = SpeechWorkflowState()
    private var activeSession: SpeechSession?
    private var isFinalRewriteInFlight = false
    private var isTranslationInFlight = false
    private var managedLLMWarmupTask: Task<Void, Never>?
    private var managedLLMRecoveryWorkItem: DispatchWorkItem?
    private var managedLLMWakeRecoveryWorkItem: DispatchWorkItem?
    private var managedLLMMemoryRecoveryNotBefore: Date?
    private var managedLLMProjectedFootprintMB = 0
    private var isCoordinatorStopping = false
    private let shadowPreviewCoordinator = ShadowPreviewCoordinator()
    /// 生产胶囊订阅统一转录核心，与可选的旁路诊断胶囊彼此独立。
    /// 见 docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md Task 2。
    private lazy var productionPreviewTextCoordinator = ProductionPreviewTextCoordinator(sink: popup)
    private let productionPreviewStateBridge = ProductionPreviewStateBridge()
    private var productionRealtimePreviewDeliveryCache = ProductionRealtimePreviewDeliveryCache()
    private var realtimeTranscriptTrace: RealtimeTranscriptTrace?
    private var shadowPreviewRuntime: ShadowTranscriptionRuntime?
    private var senseVoiceShadowProvider: SenseVoiceSnapshotProvider?
    private var mimoShadowProvider: MiMoSnapshotProvider?
    private var onlineShadowProviderName: String?
    private var onlineShadowSessionShortID: String?
    private var shadowPreviewStartTask: Task<Void, Never>?
    private var shadowPreviewEventTask: Task<Void, Never>?
    private var shadowAudioFrameTask: Task<Void, Never>?
    private var shadowAudioFrameSubscriptionID: UUID?
    private var shadowPreviewSettingObserver: NSObjectProtocol?
    private var experimentalPreviewPipeline: ExperimentalRealtimePreviewPipeline?
    private var longFormTranscriptionSession: LongFormTranscriptionSession?
    private let incrementalTranscriptStore = IncrementalTranscriptStore()
    private let longFormPersistenceQueue = DispatchQueue(
        label: "com.waykingah.typewhale.long-form-persistence",
        qos: .utility
    )
    private let longFormDiskSafetyQueue = DispatchQueue(
        label: "com.waykingah.typewhale.long-form-disk-safety",
        qos: .utility
    )
    private var longFormDiskSafetyProbeGate = LongFormDiskSafetyProbeGate(
        minimumInterval: Timing.longFormDiskSafetyProbeSeconds
    )
    private var longFormDiskSafetyProbeTaskID: UUID?
    private var longFormFinalizationTaskIDs: Set<UUID> = []
    private var pendingPasteResults: [PendingPasteResult] = []
    private var realtimeBusy = false
    private var pendingRealtimeSnapshot: RealtimeSnapshotRequest?
    private var lastProductionPreviewCompletedAt: TimeInterval?
    /// 块最终快照的待处理队列：绝不丢弃（丢了会整块预览文本消失），优先于普通中间快照处理。
    private var pendingFinalSnapshots: [RealtimeSnapshotRequest] = []
    private var activeRealtimeSnapshotID: UUID?
    private var realtimeSnapshotTimeoutWorkItem: DispatchWorkItem?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var trackedTargetTaskID: UUID?
    private var trackedTargetApp: NSRunningApplication?
    private var lastKnownPasteableTargetApp: NSRunningApplication?
    private var hotkeyIsPressed = false
    private var hotkeyPressGesturePolicy = HotkeyPressGesturePolicy(
        longPressThresholdNanoseconds: Timing.holdToRecordNanoseconds
    )
    private var longPressWorkItem: DispatchWorkItem?
    private var autoFinishWorkItem: DispatchWorkItem?
    private var initialSilenceWorkItem: DispatchWorkItem?
    private var idleASRUnloadWorkItem: DispatchWorkItem?
    private var backgroundHealthTimer: Timer?
    private var recordingSafetyTimer: Timer?
    private var capsuleStatusTimer: Timer?
    private var startupHotkeyRecoveryWorkItems: [DispatchWorkItem] = []
    private var lastMemorySafetyCheckAt = Date.distantPast
    private var lastOpenClawHealthCheckAt = Date.distantPast
    private var openClawHealthCheckInFlight = false
    private var openClawConnectionStatus: OpenClawConnectionStatus = .checking
    private var pendingOpenClawMessages: [PendingOpenClawMessage] = []
    private var openClawSendInFlight = false
    private var lastASRArenaFlushAt: Date?
    private var wakeRecoveryUntil: Date?
    private var isSystemSleeping = false
    private var didLogWakeRecoveryReloadSkip = false
    private let asrArenaFlushCooldownSeconds: TimeInterval = 30
    private var didFlushASRArenaForElevatedMemory = false
    private var suppressNextHotkeyUp = false
    private var primaryHotkeyBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.chineseStorageKey,
        fallback: .defaultBinding
    )
    private var secondaryHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.secondaryChineseStorageKey
    )
    private var screenshotHotkeyBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.screenshotStorageKey,
        fallback: .screenshotDefaultBinding
    )
    private var secondaryScreenshotHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.secondaryScreenshotStorageKey
    )
    private var screenshotTranslationHotkeyBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.screenshotTranslationStorageKey,
        fallback: .screenshotTranslationDefaultBinding
    )
    private var autoTranslateHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.autoTranslateStorageKey
    )
    private var mainWindowHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.mainWindowStorageKey
    )
    private var ideaPillHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.ideaPillStorageKey
    )
    private var openClawHotkeyBinding = HotkeyBinding.loadOpenClaw()
    private let openClawClient = OpenClawCommandClient()
    private var audioInputSwitchGeneration = AudioInputSwitchGeneration()
    private var currentRecorderInputUID = AudioInputDevice.systemDefaultUID

    init(
        controller: MainViewController,
        showMainWindow: @escaping () -> Void
    ) {
        self.controller = controller
        self.showMainWindow = showMainWindow
    }

    private func wireRemoteInput() {
        remoteInputCoordinator.onSnapshot = { [weak controller] snapshot in
            controller?.updateRemoteInputSnapshot(snapshot)
        }
        controller.onRemoteEnabledChange = { [weak self] enabled in
            self?.remoteInputCoordinator.setEnabled(enabled)
        }
        controller.onRemotePrimaryAction = { [weak self] in
            self?.remoteInputCoordinator.performPrimaryAction()
        }
        controller.onRemoteMappingChange = { [weak self] button, action in
            self?.remoteInputCoordinator.setAction(action, for: button)
        }
        controller.onRemoteResetMappings = { [weak self] in
            self?.remoteInputCoordinator.resetMappings()
        }
        remoteInputCoordinator.start()
    }

    func start() {
        isCoordinatorStopping = false
        wireRemoteInput()
        shadowPreviewCoordinator.onRenderDiagnostics = { state, drawMilliseconds in
            LaunchDiagnostics.markAsync(
                "shadow_preview_render session=\(state.sessionID.rawValue.uuidString.prefix(8)) sequence=\(state.sequence) chars=\(state.stableWindowText.count + state.volatileTailText.count) draw_ms=\(drawMilliseconds)"
            )
        }
        productionPreviewTextCoordinator.onDeliveryDiagnostics = { state, deliveredChars in
            LaunchDiagnostics.markAsync(
                "production_preview_delivery task_id=\(state.sessionID.rawValue.uuidString.prefix(8)) sequence=\(state.sequence) chars=\(deliveredChars) stable=\(state.stableCharacterCount)"
            )
        }
        if shadowPreviewSettingObserver == nil {
            shadowPreviewSettingObserver = NotificationCenter.default.addObserver(
                forName: .shadowPreviewSettingDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object as? Bool == false else { return }
                Task { @MainActor [weak self] in
                    self?.endShadowPreview(cancelled: true)
                }
            }
        }
        recorder.onBands = { [weak self] bands in
            self?.popup.updateBands(bands)
            self?.controller.updateInputBands(bands)
            self?.tickRecordingGuards()
            self?.refreshCapsuleStatusIfNeeded()
        }
        recorder.onVoiceProbe = { [weak self] taskID, samples, sampleRate in
            self?.receiveVoiceProbe(taskID: taskID, samples: samples, sampleRate: sampleRate)
        }
        recorder.onInputLevelDb = { [weak self] db in
            self?.popup.updateInputLevel(db: db)
        }
        recorder.onRealtimeSnapshot = { [weak self] taskID, samples, sampleRate, chunkIndex, isChunkFinal, audioDuration, audioRange in
            self?.receiveRealtimeSnapshot(
                taskID: taskID,
                samples: samples,
                sampleRate: sampleRate,
                chunkIndex: chunkIndex,
                isChunkFinal: isChunkFinal,
                audioDuration: audioDuration,
                audioRange: audioRange
            )
        }
        recorder.onExperimentalPreviewSnapshot = { [weak self] snapshot in
            self?.receiveExperimentalCorrectionSnapshot(snapshot)
        }
        recorder.onInputRouteEvent = { [weak self] event in
            self?.handleAudioInputRouteEvent(event)
        }
        recorder.onInputRecoveryFailed = { [weak self] message in
            guard let self else { return }
            ToastPresenter.shared.show(message, style: .error, duration: 2.6)
            self.finishRecording(reason: "audio_input_configuration_recovery_failed")
        }
        controller.updateHotkeys(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            secondaryScreenshot: secondaryScreenshotHotkeyBinding,
            screenshotTranslation: screenshotTranslationHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding,
            ideaPill: ideaPillHotkeyBinding,
            openClaw: openClawHotkeyBinding
        )
        hotkey.update(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            secondaryScreenshot: secondaryScreenshotHotkeyBinding,
            screenshotTranslation: screenshotTranslationHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding,
            ideaPill: ideaPillHotkeyBinding,
            openClaw: openClawHotkeyBinding
        )
        hotkey.onTimedDown = { [weak self] channel, purpose, binding, timing in
            self?.handleHotkeyDown(
                channel: channel,
                purpose: purpose,
                binding: binding,
                timing: timing
            )
        }
        hotkey.onTimedUp = { [weak self] channel, purpose, binding, timing in
            self?.handleHotkeyUp(
                channel: channel,
                purpose: purpose,
                binding: binding,
                timing: timing
            )
        }
        hotkey.onEscape = { [weak self] in
            self?.autoSendCountdownCoordinator.cancel(
                reason: .escapeKey
            ) ?? false
        }
        hotkey.onRightMouse = { [weak self] in
            self?.autoSendCountdownCoordinator.cancel(
                reason: .rightMouseButton
            ) ?? false
        }
        hotkey.onManualSubmitKey = { [weak self] in
            self?.autoSendCountdownCoordinator.cancel(
                reason: .manualSubmitKey
            )
        }
        hotkey.onAutoTranslateToggle = { [weak self] in self?.toggleAutoTranslateFromHotkey() }
        hotkey.onScreenshot = { [weak self] in self?.beginScreenshotFromHotkey() }
        hotkey.onScreenshotTranslation = { [weak self] in self?.beginScreenshotTranslationFromHotkey() }
        hotkey.onMainWindow = { [weak self] in self?.showMainWindowFromHotkey() }
        wirePreviewCallbacks()
        modelInstaller.onStateChange = { [weak self] state in
            self?.controller.updateModelState(state)
            if case .ready = state {
                self?.nativeASR.reload()
                self?.controller.setPrimaryStatus(
                    "等待录音",
                    detail: "\(self?.primaryHotkeyBinding.displayName ?? "Fn") 录音",
                    tone: .idle,
                    resetWaveform: true
                )
                self?.releaseASRResourcesIfMemoryElevated()
            }
        }
        funASRRuntimeInstaller.onStateChange = { [weak self] state in
            guard let self else { return }
            self.controller.updateFunASRRuntimeState(state)
            if case .ready = state {
                let backend = self.controller.asrBackend
                let wasAlreadyPersisted = AppSettingsStore.loadMainViewSettings().asrBackend == backend
                self.controller.saveSettings()
                if wasAlreadyPersisted, backend.supportsFunASRSidecarWarmup {
                    self.asr.warmUp(backend: backend)
                }
            }
        }
        controller.updateFunASRRuntimeState(funASRRuntimeInstaller.state)
        controller.onInstallModel = { [weak self] in
            guard let self else { return }
            if self.controller.asrBackend == .senseVoice {
                self.modelInstaller.install()
            } else {
                self.funASRRuntimeInstaller.install()
            }
        }
        controller.onASRBackendChange = { [weak self] backend, completion in
            guard let self else {
                completion(.failure(NSError(domain: "com.waykingah.typewhale.asr-switch", code: 1, userInfo: [NSLocalizedDescriptionKey: "识别协调器已释放"])))
                return
            }
            if backend == .senseVoice {
                self.asr.stop()
                completion(.success(()))
            } else {
                self.asr.warmUp(backend: backend) { result in
                    switch result {
                    case .success:
                        completion(.success(()))
                    case .failure(let error):
                        LaunchDiagnostics.mark("asr_selection_warmup_failed backend=\(backend.rawValue) error=\(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
        controller.onShowASRBenchmark = { [weak self] in
            guard let self else { return }
            self.benchmarkWindowController.showWindow(nil)
            self.benchmarkWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        controller.onSmartAIModelChange = { [weak self] model in
            guard let self else { return }
            if model.provider == .typeWhaleMLX {
                self.prewarmManagedLLMIfNeeded(reason: "model_selection")
            } else {
                self.stopManagedLLM(reason: "model_selection")
            }
        }
        controller.onPrimaryMicrophoneSelection = { [weak self] uid in
            self?.switchPrimaryMicrophone(to: uid)
        }
        controller.onHotkeysChange = { [weak self] primary, secondary, screenshot, secondaryScreenshot, screenshotTranslation, autoTranslate, mainWindow, ideaPill, openClaw in
            self?.primaryHotkeyBinding = primary
            self?.secondaryHotkeyBinding = secondary
            self?.screenshotHotkeyBinding = screenshot
            self?.secondaryScreenshotHotkeyBinding = secondaryScreenshot
            self?.screenshotTranslationHotkeyBinding = screenshotTranslation
            self?.autoTranslateHotkeyBinding = autoTranslate
            self?.mainWindowHotkeyBinding = mainWindow
            self?.ideaPillHotkeyBinding = ideaPill
            self?.openClawHotkeyBinding = openClaw
            self?.hotkey.update(
                primary: primary,
                secondary: secondary,
                screenshot: screenshot,
                secondaryScreenshot: secondaryScreenshot,
                screenshotTranslation: screenshotTranslation,
                autoTranslate: autoTranslate,
                mainWindow: mainWindow,
                ideaPill: ideaPill,
                openClaw: openClaw
            )
            self?.startHotkey(reason: "hotkey_update")
            self?.refreshPermissions()
        }
        modelInstaller.refresh()
        startHotkey(reason: "app_start")
        scheduleStartupHotkeyRecovery()
        senseVoiceFinalASR.start()
        if controller.asrBackend.supportsFunASRSidecarWarmup {
            asr.warmUp(backend: controller.asrBackend) { result in
                if case .failure(let error) = result {
                    LaunchDiagnostics.mark("funasr_startup_warmup_failed error=\(error.localizedDescription)")
                }
            }
        }
        realtimeASR.start()
        releaseASRResourcesIfMemoryElevated()
        startObservingTargetApplicationChanges()
        refreshPermissions()
        PermissionDiagnosticsProvider.requestAccessibilityIfNeeded()
        startBackgroundHealthTimer()
        prewarmManagedLLMIfNeeded(reason: "app_start")
    }

    func stop() {
        isCoordinatorStopping = true
        remoteInputCoordinator.stop()
        autoSendCountdownCoordinator.cancel(reason: .appStopping)
        stopBackgroundHealthTimer()
        stopRecordingSafetyTimer()
        cancelStartupHotkeyRecovery()
        longPressWorkItem?.cancel()
        hotkeyPressGesturePolicy.reset()
        hotkeyIsPressed = false
        cancelAutoFinishTimer()
        cancelInitialSilenceTimer()
        cancelIdleASRUnload()
        if recorder.isRecording || activeSession != nil {
            LaunchDiagnostics.mark(
                "recording_cancel_requested reason=coordinator_stop task_id=\(activeSession?.id.uuidString.prefix(8) ?? "-")"
            )
        }
        recorder.cancel()
        clearActiveRecording()
        cancelRecordingStopHandoff(reason: "coordinator_stop")
        pendingPasteResults.removeAll()
        cancelActiveWorkflow(reason: "coordinator_stop")
        inputState = .idle
        stopObservingTargetApplicationChanges()
        asr.stop()
        senseVoiceFinalASR.stop()
        realtimeASR.stop()
        stopManagedLLM(reason: "coordinator_stop")
    }

    func handleSystemWillPowerOff() {
        isCoordinatorStopping = true
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_will_power_off"))
        cancelRecordingForSystemSleep(reason: "power_off")
        stopManagedLLM(reason: "system_power_off")
    }

    func handleSystemWillSleep() {
        isSystemSleeping = true
        remoteInputCoordinator.suspend()
        wakeRecoveryUntil = nil
        stopBackgroundHealthTimer()
        stopRecordingSafetyTimer()
        stopCapsuleStatusTimer()
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_will_sleep"))
        cancelRecordingForSystemSleep(reason: "sleep")
        stopManagedLLM(reason: "system_sleep")
    }

    func handleSystemDidWake() {
        isSystemSleeping = false
        remoteInputCoordinator.resume()
        wakeRecoveryUntil = Date().addingTimeInterval(Timing.wakeRecoveryGraceSeconds)
        didFlushASRArenaForElevatedMemory = false
        didLogWakeRecoveryReloadSkip = false
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_did_wake"))
        managedLLMWakeRecoveryWorkItem?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.managedLLMWakeRecoveryWorkItem = nil
            guard !self.isSystemSleeping, !self.isCoordinatorStopping else { return }
            self.wakeRecoveryUntil = nil
            LaunchDiagnostics.mark(self.backgroundStateLogLine(event: "wake_recovery_check"))
            self.refreshPermissions()
            if !self.hotkey.isGlobalListening {
                self.startHotkey(reason: "wake_recovery")
            }
            self.controller.updateMemoryReadout()
            self.startBackgroundHealthTimer()
            self.evaluateManagedLLMMemoryLifecycle(
                reason: "system_wake",
                coldPrewarmAllowed: true
            )
        }
        managedLLMWakeRecoveryWorkItem = recovery
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Timing.wakeRecoveryGraceSeconds,
            execute: recovery
        )
    }

    func refreshUserVisibleDiagnostics() {
        if !hotkey.isGlobalListening, PermissionDiagnosticsProvider.current().accessibilityTrusted {
            startHotkey(reason: "visible_diagnostics")
        }
        refreshPermissions()
        controller.updateMemoryReadout()
    }

    private func startHotkey(reason: String) {
        let listening = hotkey.start()
        LaunchDiagnostics.mark(
            "hotkey_start_result reason=\(reason) listening=\(listening) accessibility_trusted=\(PermissionDiagnosticsProvider.current().accessibilityTrusted)"
        )
    }

    private func scheduleStartupHotkeyRecovery() {
        cancelStartupHotkeyRecovery()
        startupHotkeyRecoveryWorkItems = Timing.startupHotkeyRecoveryDelays.enumerated().map { index, delay in
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.hotkey.isGlobalListening {
                    LaunchDiagnostics.mark("hotkey_startup_recovery_check attempt=\(index + 1) listening=true")
                    self.cancelStartupHotkeyRecovery()
                    return
                }
                self.startHotkey(reason: "app_start_recovery_\(index + 1)")
                self.refreshPermissions()
                if self.hotkey.isGlobalListening {
                    self.cancelStartupHotkeyRecovery()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
        LaunchDiagnostics.mark("hotkey_startup_recovery_scheduled attempts=\(startupHotkeyRecoveryWorkItems.count)")
    }

    private func cancelStartupHotkeyRecovery() {
        startupHotkeyRecoveryWorkItems.forEach { $0.cancel() }
        startupHotkeyRecoveryWorkItems.removeAll()
    }

    private func prewarmManagedLLMIfNeeded(reason: String) {
        guard SmartAIModelStore.load().provider == .typeWhaleMLX else { return }
        guard MemoryMonitor.totalPhysicalMemoryMB >= 16 * 1024 else {
            LaunchDiagnostics.mark(
                "managed_mlx warmup_skip reason=\(reason) cause=physical_memory_below_16gb"
            )
            return
        }
        let service = ManagedLLMRuntimeService.shared
        let modelID = ManagedLLMModelID.qwen3_4BInstruct2507_4bit
        guard case .ready = service.runtimeState else {
            LaunchDiagnostics.mark(
                "managed_mlx warmup_skip reason=\(reason) cause=runtime_not_ready model=\(modelID.rawValue)"
            )
            return
        }

        managedLLMWarmupTask?.cancel()
        let registry = service.registry
        let runtime = service.runtime
        managedLLMWarmupTask = Task.detached(priority: .utility) {
            guard case .ready(let modelDirectory) = registry.readiness(for: modelID),
                  !Task.isCancelled else {
                LaunchDiagnostics.mark(
                    "managed_mlx warmup_skip reason=\(reason) cause=model_not_ready model=\(modelID.rawValue)"
                )
                return
            }
            let request = ManagedMLXLLMRequest(
                protocolVersion: 1,
                id: UUID().uuidString,
                command: .warmup,
                modelDirectory: modelDirectory.path,
                systemPrompt: "",
                userPrompt: "",
                reasoning: .low,
                maxTokens: 1
            )
            do {
                let response = try await runtime.perform(request)
                _ = try ManagedLLMResponseValidator.validate(response, requireFinalText: false)
                LaunchDiagnostics.mark(
                    "managed_mlx warmup_done reason=\(reason) model=\(modelID.rawValue) load_ms=\(response.metrics?.loadMS ?? -1) peak_rss_bytes=\(response.metrics?.peakRSSBytes ?? -1)"
                )
            } catch is CancellationError {
                LaunchDiagnostics.mark(
                    "managed_mlx warmup_cancelled reason=\(reason) model=\(modelID.rawValue)"
                )
                return
            } catch {
                LaunchDiagnostics.mark(
                    "managed_mlx warmup_failed reason=\(reason) model=\(modelID.rawValue) error_type=\(String(describing: type(of: error)))"
                )
                return
            }

            guard !Task.isCancelled else { return }
            do {
                let prefillResponse = try await runtime.perform(
                    ManagedLLMPrefill.request(modelDirectory: modelDirectory)
                )
                _ = try ManagedLLMResponseValidator.validate(prefillResponse, requireFinalText: true)
                let metrics = prefillResponse.metrics
                LaunchDiagnostics.mark(
                    "managed_mlx prefill_done reason=\(reason) model=\(modelID.rawValue) ttft_ms=\(metrics?.ttftMS ?? -1) prompt_tokens=\(metrics?.promptTokens ?? -1) prompt_tokens_evaluated=\(metrics?.promptTokensEvaluated ?? metrics?.promptTokens ?? -1)"
                )
            } catch is CancellationError {
                LaunchDiagnostics.mark(
                    "managed_mlx prefill_cancelled reason=\(reason) model=\(modelID.rawValue)"
                )
            } catch {
                LaunchDiagnostics.mark(
                    "managed_mlx prefill_failed reason=\(reason) model=\(modelID.rawValue) error_type=\(String(describing: type(of: error)))"
                )
            }
        }
    }

    private func cancelActiveSmartAIWork(reason: String) {
        guard SmartAIModelStore.load().provider == .typeWhaleMLX else { return }
        let service = ManagedLLMRuntimeService.shared
        let workerSnapshot = service.workerMemorySnapshot
        managedLLMProjectedFootprintMB = max(
            managedLLMProjectedFootprintMB,
            workerSnapshot.footprintMB
        )
        service.runtime.cancelCurrentRequest()
        managedLLMMemoryRecoveryNotBefore = Date().addingTimeInterval(1)
        managedLLMRecoveryWorkItem?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.managedLLMRecoveryWorkItem = nil
            guard !self.isSystemSleeping, !self.isCoordinatorStopping,
                  self.isIdleForASRResourceRelease else { return }
            self.evaluateManagedLLMMemoryLifecycle(reason: "request_cancel_recovery")
        }
        managedLLMRecoveryWorkItem = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: recovery)
        LaunchDiagnostics.mark("managed_mlx request_cancel reason=\(reason)")
    }

    private func cancelActiveWorkflow(reason: String) {
        cancelActiveSmartAIWork(reason: reason)
        workflowState.cancelActiveTask()
    }

    private func stopManagedLLM(reason: String) {
        managedLLMWakeRecoveryWorkItem?.cancel()
        managedLLMWakeRecoveryWorkItem = nil
        managedLLMRecoveryWorkItem?.cancel()
        managedLLMRecoveryWorkItem = nil
        managedLLMWarmupTask?.cancel()
        managedLLMWarmupTask = nil
        ManagedLLMRuntimeService.shared.runtime.cancelCurrentRequest()
        ManagedLLMRuntimeService.shared.stop()
        LaunchDiagnostics.mark("managed_mlx helper_stop reason=\(reason)")
    }

    private func startBackgroundHealthTimer() {
        guard backgroundHealthTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Timing.backgroundHealthSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performBackgroundHealthCheck()
            }
        }
        timer.tolerance = 5
        backgroundHealthTimer = timer
        LaunchDiagnostics.mark("background_health_timer_start interval=\(Int(Timing.backgroundHealthSeconds))")
    }

    private func stopBackgroundHealthTimer() {
        backgroundHealthTimer?.invalidate()
        backgroundHealthTimer = nil
    }

    private func performBackgroundHealthCheck() {
        guard !isSystemSleeping else { return }
        if !hotkey.isGlobalListening, PermissionDiagnosticsProvider.current().accessibilityTrusted {
            startHotkey(reason: "background_health_hotkey_recovery")
        }
        if activeSession == nil, !recorder.isRecording {
            recorder.releaseIdleInputSession(reason: "background_idle")
        }
        let now = Date()
        if now.timeIntervalSince(lastMemorySafetyCheckAt) >= Timing.memorySafetyCheckSeconds {
            lastMemorySafetyCheckAt = now
            releaseASRResourcesIfMemoryElevated()
        }
    }

    private func startRecordingSafetyTimer() {
        guard recordingSafetyTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Timing.recordingSafetySeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recorder.isRecording || self.activeSession != nil else {
                    self?.stopRecordingSafetyTimer()
                    return
                }
                self.enforceRecordingTimeoutsIfNeeded()
            }
        }
        timer.tolerance = 0.1
        recordingSafetyTimer = timer
    }

    private func stopRecordingSafetyTimer() {
        recordingSafetyTimer?.invalidate()
        recordingSafetyTimer = nil
    }

    private var isInWakeRecoveryGrace: Bool {
        guard let wakeRecoveryUntil else { return false }
        return Date() < wakeRecoveryUntil
    }

    private func cancelRecordingForSystemSleep(reason: String) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        hotkeyPressGesturePolicy.reset()
        if recorder.isRecording || activeSession != nil {
            LaunchDiagnostics.mark(
                "recording_cancel_requested reason=system_\(reason) task_id=\(activeSession?.id.uuidString.prefix(8) ?? "-")"
            )
            LaunchDiagnostics.mark("recording_safety_cancel reason=\(reason)")
            recorder.cancel()
            clearActiveRecording()
            cancelRecordingStopHandoff(reason: "system_\(reason)")
            trackedTargetTaskID = nil
            trackedTargetApp = nil
            cancelActiveWorkflow(reason: "system_\(reason)")
            inputState = .idle
            drainPendingPasteResultsIfPossible()
            controller.setPrimaryStatus(
                "录音已停止",
                detail: "系统即将\(reason == "sleep" ? "睡眠" : "关机")，已停止本次录音。",
                tone: .warning,
                resetWaveform: true
            )
            popup.hideAnimated()
        }
        discardPendingRealtimeSnapshot()
        realtimeBusy = false
        activeRealtimeSnapshotID = nil
        realtimeSnapshotTimeoutWorkItem?.cancel()
        realtimeSnapshotTimeoutWorkItem = nil
    }

    private func backgroundStateLogLine(event: String) -> String {
        [
            "background_state event=\(event)",
            "recording=\(recorder.isRecording)",
            "active_session=\(activeSession != nil)",
            "input_state=\(inputState.logName)",
            "realtime_busy=\(realtimeBusy)",
            "pending_paste=\(pendingPasteResults.count)",
            "wake_grace=\(isInWakeRecoveryGrace)",
            "memory_mb=\(MemoryMonitor.currentFootprintMB)",
        ].joined(separator: " ")
    }

    private func startCapsuleStatusTimer() {
        guard capsuleStatusTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Timing.capsuleStatusSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recorder.isRecording || self.activeSession != nil else {
                    self?.stopCapsuleStatusTimer()
                    return
                }
                self.updateCapsuleStatus()
            }
        }
        timer.tolerance = 0.1
        capsuleStatusTimer = timer
    }

    private func stopCapsuleStatusTimer() {
        capsuleStatusTimer?.invalidate()
        capsuleStatusTimer = nil
    }

    private func refreshPermissions(checkMicrophone: Bool = false) {
        let permissions = PermissionDiagnosticsProvider.current(checkMicrophone: checkMicrophone)
        let globalListening = hotkey.isGlobalListening
        UserDefaults.standard.synchronize()
        if checkMicrophone {
            controller.micStatus.stringValue = permissions.microphoneAuthorized ? "● 已开启" : "● 未开启"
            controller.micStatus.textColor = permissions.microphoneAuthorized ? UITheme.brandGreen : .systemRed
        } else {
            controller.micStatus.stringValue = "● 录音时确认"
            controller.micStatus.textColor = .secondaryLabelColor
        }
        controller.accessibilityStatus.stringValue = permissions.accessibilityTrusted ? "● 已开启" : "● 未开启"
        controller.accessibilityStatus.textColor = permissions.accessibilityTrusted ? UITheme.brandGreen : .systemRed
        controller.screenRecordingStatus.stringValue = permissions.screenRecordingAuthorized ? "● 已开启" : "● 未开启"
        controller.screenRecordingStatus.textColor = permissions.screenRecordingAuthorized ? UITheme.brandGreen : .systemRed
        if globalListening {
            controller.hotkeyStatus.stringValue = "● 监听中"
            controller.hotkeyStatus.textColor = UITheme.brandGreen
        } else {
            controller.hotkeyStatus.stringValue = "● 未监听"
            controller.hotkeyStatus.textColor = .systemOrange
        }
    }

    private func startObservingTargetApplicationChanges() {
        guard workspaceActivationObserver == nil else { return }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleActivatedApplication(notification)
            }
        }
    }

    private func stopObservingTargetApplicationChanges() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        workspaceActivationObserver = nil
    }

    private func handleActivatedApplication(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let target = pasteableTargetApp(app) {
            lastKnownPasteableTargetApp = target
        }
        guard trackedTargetTaskID != nil else { return }
        updateTrackedTargetApp(app)
    }

    @discardableResult
    private func refreshTrackedTargetFromFrontmost() -> NSRunningApplication? {
        updateTrackedTargetApp(NSWorkspace.shared.frontmostApplication)
        return trackedTargetApp
    }

    private func updateTrackedTargetApp(_ app: NSRunningApplication?) {
        guard trackedTargetTaskID != nil else { return }
        // 只有遇到有效可粘贴目标才更新；瞬时非粘贴前台（TypeWhale 自身胶囊/窗口、桌面等）
        // 或系统控制中心/菜单栏弹窗不清空已知的好目标，避免「识别成功却找不到粘贴目标」。
        if let target = pasteableTargetApp(app) {
            trackedTargetApp = target
            lastKnownPasteableTargetApp = target
            if var session = activeSession, session.id == trackedTargetTaskID {
                session.targetApp = target
                activeSession = session
            }
        } else if let app {
            LaunchDiagnostics.mark(
                "target_tracking_ignored app=\(Self.logApp(app)) reason=not_pasteable current=\(Self.logApp(trackedTargetApp))"
            )
        }
        let display = trackedTargetApp ?? app
        popup.updateTargetApp(
            appIcon: display?.icon,
            appName: displayNameForSelectedTarget(display)
        )
        if let session = activeSession {
            updateCapsuleModePresentation(
                purpose: session.purpose,
                targetApp: trackedTargetApp ?? session.targetApp
            )
        }
    }

    private func currentTargetApp(for task: RecordingTask) -> NSRunningApplication? {
        currentTargetApp(taskID: task.id, fallback: task.targetApp)
    }

    private func currentTargetApp(taskID: UUID, fallback: NSRunningApplication?) -> NSRunningApplication? {
        guard trackedTargetTaskID == taskID else { return fallback }
        if let trackedTargetApp, !trackedTargetApp.isTerminated {
            return trackedTargetApp
        }
        // 实时跟踪的目标被瞬时非粘贴前台（如 TypeWhale 自己的胶囊/窗口）清空时，
        // 回退到录音开始时捕获的目标，避免第二次起录音「识别成功却不粘贴」。
        if let fallback, !fallback.isTerminated {
            return fallback
        }
        return nil
    }

    private func pasteableTargetApp(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, !app.isTerminated else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        if app.activationPolicy != .regular {
            return nil
        }
        if isTransientSystemUIApp(app) {
            return nil
        }
        guard app.localizedName?.isEmpty == false else {
            return nil
        }
        return app
    }

    private func reusableLastKnownTarget(for frontmostApp: NSRunningApplication?) -> NSRunningApplication? {
        guard let frontmostApp,
              isTransientSystemUIApp(frontmostApp),
              let target = lastKnownPasteableTargetApp,
              !target.isTerminated else {
            return nil
        }
        return target
    }

    private func isTransientSystemUIApp(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? ""
        let blockedBundleIDs: Set<String> = [
            "com.apple.ControlCenter",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.bjango.istatmenus.status",
            "com.bjango.istatmenus.agent",
        ]
        if blockedBundleIDs.contains(bundleID) {
            return true
        }
        let loweredName = name.lowercased()
        return loweredName == "control center" ||
            loweredName == "控制中心" ||
            loweredName == "notification center" ||
            loweredName == "通知中心" ||
            loweredName == "systemuiserver" ||
            loweredName.contains("menubar")
    }

    private static func logApp(_ app: NSRunningApplication?) -> String {
        guard let app else { return "nil" }
        let name = app.localizedName ?? "unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"
        return "\(name)[\(bundleID)#\(app.processIdentifier)]"
    }

    private func displayNameForSelectedTarget(_ app: NSRunningApplication?) -> String {
        guard let app, !app.isTerminated else {
            return "未选择目标"
        }
        if let name = app.localizedName, !name.isEmpty {
            if pasteableTargetApp(app) == nil,
               app.bundleIdentifier != Bundle.main.bundleIdentifier,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return "\(name)（不可粘贴）"
            }
            return name
        }
        return "不可粘贴目标"
    }

    private func endTargetTrackingIfNeeded(_ taskID: UUID) {
        guard trackedTargetTaskID == taskID else { return }
        trackedTargetTaskID = nil
        trackedTargetApp = nil
    }

    private func handleHotkeyDown(
        channel: SpeechInputChannel,
        purpose: SpeechInputPurpose,
        binding: HotkeyBinding,
        timing: HotkeyEventTiming
    ) {
        LaunchDiagnostics.mark(
            "hotkey_handler phase=down purpose=\(purpose.logName) binding=\(binding.displayName) input_state=\(inputState.logName) active_session=\(activeSession != nil) recorder_recording=\(recorder.isRecording)"
        )
        if screenshotCoordinator.isActive { return }
        if purpose == .openClawChat {
            activateOpenClawRecording(channel: channel, binding: binding)
            return
        }
        if binding.kind == .mediaPlay {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            hotkeyIsPressed = false
            hotkeyPressGesturePolicy.reset()
            if let activeSession {
                if activeSession.captureSource != .microphone ||
                    !activeSession.matchesTrigger(channel: channel, purpose: purpose) {
                    queueRecordingReplacement(
                        instructions: "再次按 \(binding.displayName) 完成录音",
                        activation: .toggle,
                        channel: channel,
                        purpose: purpose
                    )
                }
                finishRecording(reason: "media_trigger")
            } else if recorder.isRecording {
                finishRecording()
            } else {
                startRecording(
                    instructions: "再次按 \(binding.displayName) 完成录音",
                    activation: .toggle,
                    channel: channel,
                    purpose: purpose
                )
            }
            return
        }
        hotkeyIsPressed = true
        longPressWorkItem?.cancel()
        let pressID = hotkeyPressGesturePolicy.begin(at: timing)

        let displayName = binding.displayName
        if let activeSession {
            // 我开、我关：同一入口按下不结束，仍交给 key-up 按 toggle 语义收尾。
            // 我开、他开：不同入口先完成当前录音的任务级资源交接，再开启新入口。
            if activeSession.captureSource == .microphone,
               activeSession.matchesTrigger(channel: channel, purpose: purpose) {
                return
            }
            suppressNextHotkeyUp = true
            queueRecordingReplacement(
                instructions: "再次按下 \(displayName) 完成录音",
                activation: .toggle,
                channel: channel,
                purpose: purpose
            )
            finishRecording()
            return
        }
        guard !recorder.isRecording else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hotkeyIsPressed, !self.recorder.isRecording else { return }
            guard self.hotkeyPressGesturePolicy.markHoldActivated(pressID: pressID) else { return }
            LaunchDiagnostics.mark(
                "hotkey_gesture phase=threshold press_id=\(pressID) classification=long threshold_ms=\(Timing.holdToRecordNanoseconds / 1_000_000)"
            )
            self.startRecording(
                instructions: "松开 \(displayName) 完成录音",
                activation: .hold,
                channel: channel,
                purpose: purpose
            )
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.holdToRecordSeconds, execute: workItem)
    }

    private func handleHotkeyUp(
        channel: SpeechInputChannel,
        purpose: SpeechInputPurpose,
        binding: HotkeyBinding,
        timing: HotkeyEventTiming
    ) {
        let gestureDecision = hotkeyPressGesturePolicy.release(at: timing)
        let gestureDuration = gestureDecision.durationMilliseconds.map(String.init) ?? "unknown"
        LaunchDiagnostics.mark(
            "hotkey_gesture phase=classified purpose=\(purpose.logName) binding=\(binding.displayName) decision=\(gestureDecision.logName) duration_ms=\(gestureDuration) threshold_ms=\(Timing.holdToRecordNanoseconds / 1_000_000)"
        )
        LaunchDiagnostics.mark(
            "hotkey_handler phase=up purpose=\(purpose.logName) binding=\(binding.displayName) input_state=\(inputState.logName) active_session=\(activeSession != nil) recorder_recording=\(recorder.isRecording)"
        )
        if purpose == .openClawChat {
            hotkeyIsPressed = false
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            suppressNextHotkeyUp = false
            return
        }
        if binding.kind == .mediaPlay {
            return
        }
        hotkeyIsPressed = false
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        if screenshotCoordinator.isActive { return }
        if suppressNextHotkeyUp {
            suppressNextHotkeyUp = false
            return
        }
        let displayName = binding.displayName

        switch activeSession?.activation {
        case .hold, .toggle:
            let shouldStartReplacement = shouldReplaceActiveRecording(channel: channel, purpose: purpose)
            if shouldStartReplacement {
                queueRecordingReplacement(
                    instructions: "再次按下 \(displayName) 完成录音",
                    activation: .toggle,
                    channel: channel,
                    purpose: purpose
                )
            }
            finishRecording()
        case nil:
            guard !recorder.isRecording else {
                finishRecording()
                return
            }
            if case .longPress(_, let holdActivated) = gestureDecision,
               !holdActivated {
                LaunchDiagnostics.mark(
                    "hotkey_gesture phase=recovered decision=long action=suppress_toggle reason=threshold_callback_delayed"
                )
                return
            }
            startRecording(
                instructions: "再次按下 \(displayName) 完成录音",
                activation: .toggle,
                channel: channel,
                purpose: purpose
            )
        }
    }

    private func activateOpenClawRecording(channel: SpeechInputChannel, binding: HotkeyBinding) {
        hotkeyIsPressed = false
        hotkeyPressGesturePolicy.reset()
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        let displayName = binding.actionDisplayName

        if let activeSession {
            if activeSession.captureSource != .microphone ||
                !activeSession.matchesTrigger(channel: channel, purpose: .openClawChat) {
                queueRecordingReplacement(
                    instructions: "再次触发 \(displayName) 完成 OpenClaw 录音",
                    activation: .toggle,
                    channel: channel,
                    purpose: .openClawChat
                )
            }
            finishRecording(reason: "openclaw_replacement")
            return
        }

        if recorder.isRecording {
            finishRecording()
            return
        }

        startRecording(
            instructions: "再次触发 \(displayName) 完成 OpenClaw 录音",
            activation: .toggle,
            channel: channel,
            purpose: .openClawChat
        )
    }

    private func toggleAutoTranslateFromHotkey() {
        controller.toggleAutoTranslateFromShortcut()
        popup.updateAutoTranslateEnabled(controller.autoTranslateEnabled)
    }

    private func showMainWindowFromHotkey() {
        showMainWindow()
    }

    private func cancelCurrentOperationFromRemote() {
        if let session = activeSession, session.captureSource.isRemote {
            cancelRemoteSpeech(taskID: session.id)
            return
        }
        _ = autoSendCountdownCoordinator.cancel(reason: .escapeKey)
    }

    private func cycleSmartRewriteModeFromCapsule() {
        if activeSession?.purpose == .ideaPill || activeSession?.purpose == .openClawChat {
            popup.updateModeName(activeSession?.purpose.capsuleModeName ?? SpeechInputPurpose.ideaPill.capsuleModeName)
            popup.updateModeEmphasis(.normal)
            return
        }
        let next = controller.cycleSmartRewritePreference()
        let presentation = capsuleModePresentation(
            preference: next,
            purpose: .dictation,
            targetApp: trackedTargetApp ?? activeSession?.targetApp
        )
        popup.updateModeName(presentation.modeName)
        popup.updateModeEmphasis(presentation.emphasis)
    }

    private func updateCapsuleModePresentation(
        purpose: SpeechInputPurpose,
        targetApp: NSRunningApplication?
    ) {
        let presentation = capsuleModePresentation(
            preference: controller.smartRewritePreference,
            purpose: purpose,
            targetApp: targetApp
        )
        popup.updateModeName(presentation.modeName)
        popup.updateModeEmphasis(presentation.emphasis)
    }

    private func capsuleModePresentation(
        preference: SmartRewritePreference,
        purpose: SpeechInputPurpose,
        targetApp: NSRunningApplication?
    ) -> CapsuleModePresentation {
        if purpose == .ideaPill || purpose == .openClawChat {
            return CapsuleModePresentation(
                modeName: purpose.capsuleModeName,
                emphasis: .normal
            )
        }

        guard preference == .automatic else {
            return CapsuleModePresentation(
                modeName: preference.displayName,
                emphasis: .normal
            )
        }

        let progress = smartInputRouter.progressInfo(
            preference: preference,
            context: SmartInputContext(targetApp: targetApp)
        )
        return CapsuleModePresentation(
            modeName: progress.mode.displayName,
            emphasis: .automaticResolved
        )
    }

    /// 重连预览回调（主题切换换实现后需重设）。
    private func wirePreviewCallbacks() {
        popup.onCycleMode = { [weak self] in self?.cycleSmartRewriteModeFromCapsule() }
    }

    /// 按设置切换实时预览主题（默认胶囊 / 刘海）。在录音开始前调用，切换下次录音生效。
    /// 仅当目标主题与当前实现不一致时才替换，避免无谓重建。
    private func applyPreviewTheme(_ theme: PreviewTheme) {
        LaunchDiagnostics.mark(
            "preview_theme_apply requested=\(theme.rawValue) current=\(activePreviewTheme.rawValue)"
        )
        guard theme != activePreviewTheme else { return }
        popup.hideAnimated()
        switch theme {
        case .classic:
            popup = RecordingPanel()
        case .notch:
            popup = NotchPreviewPresenter()
        case .minimalBlack:
            popup = MinimalBlackPreviewPresenter()
        }
        wirePreviewCallbacks()
        productionPreviewTextCoordinator.replaceSink(popup)
        activePreviewTheme = theme
    }

    private func refreshCapsuleStatusIfNeeded() {
        let now = Date()
        if let lastCapsuleStatusUpdateAt,
           now.timeIntervalSince(lastCapsuleStatusUpdateAt) < 1 {
            return
        }
        lastCapsuleStatusUpdateAt = now
        updateCapsuleStatus()
    }

    /// 驱动胶囊状态：录音时显示剩余时长倒计时，内存偏高时高亮提示。
    private func updateCapsuleStatus() {
        let memoryHigh = controller.isMemoryElevated
        if recorder.isRecording, let startedAt = recordingStartedAt {
            let maximum = Timing.maxRecordingSeconds
            let remaining = max(0, Int((maximum - Date().timeIntervalSince(startedAt)).rounded()))
            popup.updateRecordingStatus(remainingSeconds: remaining, memoryHigh: memoryHigh)
        } else {
            popup.updateRecordingStatus(remainingSeconds: nil, memoryHigh: memoryHigh)
        }
        refreshOpenClawConnectionStatusForCapsuleIfNeeded()
    }

    private func refreshOpenClawConnectionStatusForCapsuleIfNeeded(force: Bool = false) {
        guard recorder.isRecording || activeSession != nil else { return }
        guard activeSession?.purpose == .openClawChat else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastOpenClawHealthCheckAt) >= Timing.openClawHealthProbeSeconds else {
            popup.updateOpenClawConnectionStatus(openClawConnectionStatus)
            return
        }
        guard !openClawHealthCheckInFlight else {
            popup.updateOpenClawConnectionStatus(openClawConnectionStatus)
            return
        }
        lastOpenClawHealthCheckAt = now
        openClawHealthCheckInFlight = true
        updateOpenClawCapsuleConnectionStatus(.checking)
        let settings = controller.openClawSettings
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.openClawClient.health(settings: settings, timeoutSeconds: 2)
                await MainActor.run {
                    self.openClawHealthCheckInFlight = false
                    self.updateOpenClawCapsuleConnectionStatus(.connected)
                    LaunchDiagnostics.mark("openclaw capsule_health connected=true")
                }
            } catch {
                await MainActor.run {
                    self.openClawHealthCheckInFlight = false
                    self.updateOpenClawCapsuleConnectionStatus(.unavailable)
                    LaunchDiagnostics.mark("openclaw capsule_health connected=false error=\"\(error.localizedDescription)\"")
                }
            }
        }
    }

    private func updateOpenClawCapsuleConnectionStatus(_ status: OpenClawConnectionStatus) {
        openClawConnectionStatus = status
        popup.updateOpenClawConnectionStatus(status)
    }

    private func beginScreenshotFromHotkey() {
        beginScreenshotFromHotkey(translateAfterSelection: false)
    }

    private func beginScreenshotTranslationFromHotkey() {
        beginScreenshotFromHotkey(translateAfterSelection: true)
    }

    private func beginScreenshotFromHotkey(translateAfterSelection: Bool) {
        if activeSession == nil, !recorder.isRecording {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            hotkeyIsPressed = false
            hotkeyPressGesturePolicy.reset()
        }
        LaunchDiagnostics.mark(
            "screenshot_hotkey_begin keep_main_window_state=true recording=\(recorder.isRecording) active_session=\(activeSession != nil)"
        )
        if translateAfterSelection {
            screenshotCoordinator.beginTranslation()
        } else {
            screenshotCoordinator.begin()
        }
    }

    private func startRecording(
        instructions: String,
        activation: RecordingActivation,
        channel: SpeechInputChannel? = nil,
        purpose: SpeechInputPurpose = .dictation,
        captureSource: SpeechCaptureSource = .microphone
    ) {
        guard !recorder.isRecording else { return }
        guard longFormFinalizationTaskIDs.isEmpty else {
            controller.setPrimaryStatus(
                "长录音正在收尾",
                detail: "增量转录正在安全落盘，完成后即可开始下一次录音。",
                tone: .processing
            )
            popup.show(state: "正在收尾", draft: "请稍候，正在保存上一段长录音")
            return
        }
        if captureSource.requiresMicrophonePermission {
            switch PermissionDiagnosticsProvider.microphoneAccessState() {
            case .authorized:
                break
            case .notDetermined:
                controller.setPrimaryStatus("需要麦克风权限", detail: "允许后将继续录音", tone: .warning)
                LaunchDiagnostics.mark("permission_prompt service=microphone source=recording_start")
                PermissionDiagnosticsProvider.requestMicrophone { [weak self] granted in
                    guard let self else { return }
                    self.refreshPermissions(checkMicrophone: true)
                    LaunchDiagnostics.mark("permission_result service=microphone granted=\(granted)")
                    if granted {
                        self.startRecording(
                            instructions: instructions,
                            activation: activation,
                            channel: channel,
                            purpose: purpose,
                            captureSource: captureSource
                        )
                    } else {
                        self.controller.setPrimaryStatus("麦克风未授权", detail: "请在系统设置中开启 \(AppBrand.displayName) 麦克风权限", tone: .error)
                    }
                }
                return
            case .denied:
                refreshPermissions(checkMicrophone: true)
                controller.setPrimaryStatus("麦克风未授权", detail: "请在系统设置中开启 \(AppBrand.displayName) 麦克风权限", tone: .error)
                return
            }
        }
        autoSendCountdownCoordinator.cancel(reason: .newRecording)
        cancelIdleASRUnload()
        discardPendingRealtimeSnapshot()
        didFlushASRArenaForElevatedMemory = false
        startRecordingSafetyTimer()
        startCapsuleStatusTimer()
        let selectedBackend = controller.activeASRBackend
        let capsulePreviewEnabled = controller.realtimePreviewEnabled
        let realtimeDataEnabled = true
        let experimentalSettings = controller.experimentalPreviewSettings.normalized(
            supportsSenseVoice: true
        )
        let taskID = UUID()
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let initialTargetApp = pasteableTargetApp(frontmostApp) ?? reusableLastKnownTarget(for: frontmostApp)
        LaunchDiagnostics.mark(
            "target_tracking_start task_id=\(taskID.uuidString.prefix(8)) frontmost=\(Self.logApp(frontmostApp)) initial_target=\(Self.logApp(initialTargetApp))"
        )
        let session = SpeechSession(
            id: taskID,
            channel: channel ?? .chinese,
            targetApp: initialTargetApp,
            configuration: ASRConfiguration(languageMode: .chinese, backend: selectedBackend),
            activation: activation,
            captureSource: captureSource,
            purpose: purpose,
            realtimeEnabled: realtimeDataEnabled,
            experimentalPreviewSettings: experimentalSettings,
            reRecognizeWholeRecordingAfterStop: controller.reRecognizeWholeRecordingAfterStopEnabled,
            latestPreviewText: ""
        )
        activeSession = session
        let transcriptTrace = RealtimeTranscriptTrace(sessionID: taskID)
        realtimeTranscriptTrace = transcriptTrace
        longFormDiskSafetyProbeGate.reset()
        longFormDiskSafetyProbeTaskID = nil
        if experimentalSettings.longFormIncrementalOutputEnabled {
            longFormTranscriptionSession = LongFormTranscriptionSession(maxDuration: Timing.maxRecordingSeconds)
            do {
                try incrementalTranscriptStore.begin(sessionID: taskID, startedAt: Date())
            } catch {
                LaunchDiagnostics.mark("long_form_store_begin_failed task_id=\(taskID.uuidString.prefix(8)) error=\(error.localizedDescription)")
            }
        } else {
            longFormTranscriptionSession = nil
        }
        if experimentalSettings.correctedPreviewEnabled {
            experimentalPreviewPipeline = ExperimentalRealtimePreviewPipeline(
                sessionID: taskID,
                epoch: 1,
                configuration: session.configuration,
                transcriber: nativeASR,
                transcriptTrace: transcriptTrace
            ) { [weak self] state in
                self?.applyExperimentalPreviewState(state, taskID: taskID)
            }
        } else {
            experimentalPreviewPipeline = nil
        }
        trackedTargetTaskID = taskID
        trackedTargetApp = initialTargetApp
        workflowState.startRecording(taskID: taskID)
        inputState = .recording(taskID)
        controller.updateRealtimeDraft("正在等待第一段实时文本…")
        controller.setPrimaryStatus("录音中", detail: instructions, tone: .listening)
        applyPreviewTheme(purpose == .ideaPill || purpose == .openClawChat ? .classic : controller.previewTheme)
        popup.updateAccent(previewAccent(for: purpose))
        if purpose == .openClawChat {
            updateOpenClawCapsuleConnectionStatus(.checking)
            refreshOpenClawConnectionStatusForCapsuleIfNeeded(force: true)
        }
        LaunchDiagnostics.mark(
            "capsule_show_requested task_id=\(taskID.uuidString.prefix(8)) theme=\(activePreviewTheme.rawValue) state=recording"
        )
        popup.show(state: "录音中", draft: "")
        beginProductionPreview(taskID: taskID, deliversText: capsulePreviewEnabled)
        beginShadowPreview(taskID: taskID)
        let displayedTargetApp = initialTargetApp ?? frontmostApp
        let modePresentation = capsuleModePresentation(
            preference: controller.smartRewritePreference,
            purpose: purpose,
            targetApp: initialTargetApp
        )
        popup.setContext(
            appIcon: displayedTargetApp?.icon,
            appName: displayNameForSelectedTarget(displayedTargetApp),
            modeName: modePresentation.modeName,
            autoTranslateEnabled: controller.autoTranslateEnabled && purpose == .dictation
        )
        popup.updateModeEmphasis(modePresentation.emphasis)
        systemMediaPlaybackController.pauseIfNeeded(
            enabled: controller.pauseSystemMediaWhileRecordingEnabled
        )
        outputAudioDucker.duckIfNeeded(enabled: controller.duckSystemAudioWhileRecordingEnabled)
        do {
            try startRecorder(
                taskID: taskID,
                captureSource: captureSource,
                realtimeEnabled: realtimeDataEnabled,
                experimentalPreviewEnabled: experimentalSettings.correctedPreviewEnabled
            )
            let startedAt = Date()
            recordingStartedAt = startedAt
            lastCapsuleStatusUpdateAt = nil
            updateCapsuleStatus()
            lastVoiceAt = nil
            voiceEverDetected = false
            voiceProbeInFlight = false
            voiceProbeSequence = 0
            latestVoiceProbeHasSpeech = nil
            latestVoiceProbeCapturedAt = nil
            pendingVoiceProbes.removeAll()
            autoFinishPolicy.reset(startedAt: startedAt)
            // Silero VAD 随 app 内置，正常情况下始终可用；探测出错时会在 receiveVoiceProbe 里置 false。
            voiceDetectionAvailable = vadBridge.isVoiceActivityDetectionAvailable
            LaunchDiagnostics.mark(
                "recording_start task_id=\(taskID.uuidString) purpose=\(purpose.logName) activation=\(activation) realtime_data=\(realtimeDataEnabled) capsule_preview=\(capsulePreviewEnabled) voice_detect=\(voiceDetectionAvailable ? "silero" : "off")"
            )
        } catch {
            LaunchDiagnostics.mark("recording_start_failed error=\(error.localizedDescription)")
            cancelAutoFinishTimer()
            recorder.cancel()
            clearActiveRecording()
            cancelActiveWorkflow(reason: "recording_start_failed")
            inputState = .idle
            controller.setPrimaryStatus("无法开始录音", detail: error.localizedDescription, tone: .error, resetWaveform: true)
            popup.show(state: "录音失败")
        }
    }

    private func startRecorder(
        taskID: UUID,
        captureSource: SpeechCaptureSource,
        realtimeEnabled: Bool,
        experimentalPreviewEnabled: Bool
    ) throws {
        let startBegin = Date()
        switch captureSource {
        case .remote(let sampleRate):
            try recorder.startExternal(
                taskID: taskID,
                sampleRate: sampleRate,
                realtimeEnabled: realtimeEnabled,
                sourceName: "遥控器",
                experimentalPreviewEnabled: experimentalPreviewEnabled
            )
            currentRecorderInputUID = "typewhale.remote"
            LaunchDiagnostics.mark([
                "recorder_start_ms=\(Int(Date().timeIntervalSince(startBegin) * 1000))",
                "voice_processing=false",
                "audio_input=remote_atvv",
                "audio_rate=\(sampleRate)",
                "retry_capture=none",
            ].joined(separator: " "))
        case .microphone:
            var inputDeviceResolution = AudioInputDeviceProvider.resolveSelectedInput(
                preferBuiltInMicForBluetoothSystemDefault: controller.preferBuiltInMicForBluetoothAudioEnabled
            )
            if RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
                remoteFeatureEnabled: remoteInputCoordinator.isEnabled,
                selectedDeviceName: inputDeviceResolution.matchedDeviceName
            ) {
                AudioInputDevice.saveSelectedUID(AudioInputDevice.systemDefaultUID)
                controller.refreshAudioInputDeviceMenu(selectedUID: AudioInputDevice.systemDefaultUID)
                inputDeviceResolution = AudioInputDeviceProvider.resolveSelectedInput(
                    preferBuiltInMicForBluetoothSystemDefault: controller.preferBuiltInMicForBluetoothAudioEnabled
                )
                let migratedInputName = inputDeviceResolution.matchedDeviceName
                    ?? AudioInputDeviceProvider.defaultInputDeviceName()
                    ?? "系统默认麦克风"
                controller.audioInputStatus.stringValue = "已切回：\(migratedInputName)"
                controller.detail.stringValue = "原生遥控器已启用，电脑录音已切回 \(migratedInputName)。"
                ToastPresenter.shared.show(
                    "电脑录音已切回 \(migratedInputName)",
                    style: .success,
                    duration: 2.4
                )
                LaunchDiagnostics.mark(
                    "audio_input_selection_migrated reason=legacy_remote_virtual_device"
                )
            }
            if inputDeviceResolution.didDowngradeToSystemDefault {
                controller.refreshAudioInputDeviceMenu(selectedUID: AudioInputDevice.systemDefaultUID)
                controller.detail.stringValue = "上次选择的麦克风不可用，已改为跟随系统输入。"
                LaunchDiagnostics.mark(
                    "audio_input_selection_downgrade reason=start_missing selected_uid=\(inputDeviceResolution.selectedUID)"
                )
            }
            let systemDefaultConcreteDeviceID = inputDeviceResolution.deviceID == nil
                ? AudioInputDeviceProvider.currentDefaultInputDeviceID()
                : nil
            var captureDeviceID = inputDeviceResolution.deviceID ?? systemDefaultConcreteDeviceID
            var captureInputName = inputDeviceResolution.matchedDeviceName
                ?? AudioInputDeviceProvider.defaultInputDeviceName()
                ?? "系统默认"
            var didFallbackToAVAudioEngineDefault = false
            do {
                try recorder.start(
                    taskID: taskID,
                    realtimeEnabled: realtimeEnabled,
                    inputDeviceID: captureDeviceID,
                    inputDeviceName: captureInputName,
                    experimentalPreviewEnabled: experimentalPreviewEnabled
                )
            } catch {
                if captureDeviceID != nil {
                    LaunchDiagnostics.mark(
                        "audio_input_selection_downgrade reason=bind_failed selected_uid=\(inputDeviceResolution.selectedUID) error=\(error.localizedDescription)"
                    )
                    AudioInputDevice.saveSelectedUID(AudioInputDevice.systemDefaultUID)
                    controller.refreshAudioInputDeviceMenu(selectedUID: AudioInputDevice.systemDefaultUID)
                    controller.detail.stringValue = inputDeviceResolution.deviceID == nil
                        ? "系统默认麦克风显式采集失败，已改用系统录音路径。"
                        : "选中的麦克风无法使用，已改为跟随系统输入。"
                    inputDeviceResolution = AudioInputDeviceProvider.ManualSelectionResolution(
                        deviceID: nil,
                        selectedUID: AudioInputDevice.systemDefaultUID,
                        matchedDeviceName: nil,
                        didDowngradeToSystemDefault: true,
                        usesPreferredBuiltInMic: false
                    )
                    captureDeviceID = nil
                    captureInputName = AudioInputDeviceProvider.defaultInputDeviceName() ?? "系统默认"
                    didFallbackToAVAudioEngineDefault = true
                    try recorder.start(
                        taskID: taskID,
                        realtimeEnabled: realtimeEnabled,
                        inputDeviceID: nil,
                        inputDeviceName: captureInputName,
                        experimentalPreviewEnabled: experimentalPreviewEnabled
                    )
                } else {
                    throw error
                }
            }
            currentRecorderInputUID = inputDeviceResolution.deviceID == nil
                ? AudioInputDevice.systemDefaultUID
                : inputDeviceResolution.selectedUID
            LaunchDiagnostics.mark([
                "recorder_start_ms=\(Int(Date().timeIntervalSince(startBegin) * 1000))",
                "voice_processing=false",
                "audio_input=\(inputDeviceResolution.usesPreferredBuiltInMic ? "system_preferred_built_in" : (inputDeviceResolution.deviceID == nil && captureDeviceID != nil ? "system_default_coreaudio" : (captureDeviceID == nil ? "system_default" : "manual")))",
                "audio_input_name=\(captureInputName)",
                "retry_capture=\(didFallbackToAVAudioEngineDefault ? "av_audio_engine_default" : "none")",
            ].joined(separator: " "))
        }
    }

    func beginRemoteSpeech(sampleRate: Int) -> UUID? {
        guard sampleRate == 8_000 || sampleRate == 16_000,
              activeSession == nil,
              !recorder.isRecording,
              longFormFinalizationTaskIDs.isEmpty,
              case .idle = inputState else { return nil }
        startRecording(
            instructions: "松开遥控器语音键后完成识别",
            activation: .hold,
            channel: .chinese,
            purpose: .dictation,
            captureSource: .remote(sampleRate: sampleRate)
        )
        guard let session = activeSession,
              session.captureSource.isRemote,
              recorder.isRecording else { return nil }
        return session.id
    }

    func appendRemotePCM16(_ samples: [Int16], taskID: UUID) {
        guard let session = activeSession,
              session.id == taskID,
              session.captureSource.isRemote,
              recorder.isRecording else { return }
        recorder.appendExternalPCM16(samples, taskID: taskID)
    }

    func endRemoteSpeech(taskID: UUID) {
        guard let session = activeSession,
              session.id == taskID,
              session.captureSource.isRemote else { return }
        finishRecording(reason: "remote_voice_release")
    }

    func cancelRemoteSpeech(taskID: UUID) {
        guard let session = activeSession,
              session.id == taskID,
              session.captureSource.isRemote else { return }
        LaunchDiagnostics.mark(
            "recording_cancel_requested reason=remote_disconnect task_id=\(taskID.uuidString.prefix(8))"
        )
        recorder.cancel()
        clearActiveRecording()
        cancelRecordingStopHandoff(reason: "remote_disconnect")
        trackedTargetTaskID = nil
        trackedTargetApp = nil
        cancelActiveWorkflow(reason: "remote_disconnect")
        inputState = .idle
        drainPendingPasteResultsIfPossible()
        controller.setPrimaryStatus(
            "遥控器已断开",
            detail: "本次语音已安全停止，连接恢复后可重新说话。",
            tone: .warning,
            resetWaveform: true
        )
        popup.hideAnimated()
    }

    var isSpeechPipelineBusy: Bool {
        if activeSession != nil || recorder.isRecording { return true }
        switch inputState {
        case .idle, .failed:
            return false
        case .recording, .finalizing, .pasting:
            return true
        }
    }

    private func previewAccent(for purpose: SpeechInputPurpose) -> PreviewAccent {
        switch purpose {
        case .dictation:
            return .normal
        case .ideaPill:
            return .ideaPill
        case .openClawChat:
            return .openClaw
        }
    }

    private func shouldReplaceActiveRecording(channel: SpeechInputChannel, purpose: SpeechInputPurpose) -> Bool {
        guard let activeSession else { return false }
        return activeSession.captureSource != .microphone ||
            !activeSession.matchesTrigger(channel: channel, purpose: purpose)
    }

    private func queueRecordingReplacement(
        instructions: String,
        activation: RecordingActivation,
        channel: SpeechInputChannel,
        purpose: SpeechInputPurpose,
        captureSource: SpeechCaptureSource = .microphone
    ) {
        pendingRecordingStart = PendingRecordingStart(
            instructions: instructions,
            activation: activation,
            channel: channel,
            purpose: purpose,
            captureSource: captureSource
        )
        LaunchDiagnostics.mark(
            "recording_replacement_queued purpose=\(purpose.logName) source=\(captureSource.isRemote ? "remote" : "microphone")"
        )
    }

    private func completeRecordingStopHandoff(taskID: UUID, outcome: String) {
        guard recordingStopHandoff.complete(taskID: taskID) else {
            LaunchDiagnostics.mark(
                "recording_stop_handoff phase=completion_ignored task_id=\(taskID.uuidString.prefix(8)) outcome=\(outcome)"
            )
            return
        }
        LaunchDiagnostics.mark(
            "recording_stop_handoff phase=completed task_id=\(taskID.uuidString.prefix(8)) outcome=\(outcome)"
        )
        guard let request = pendingRecordingStart else { return }
        guard activeSession == nil, !recorder.isRecording else {
            LaunchDiagnostics.mark(
                "recording_replacement_deferred reason=capture_not_released task_id=\(taskID.uuidString.prefix(8))"
            )
            return
        }
        pendingRecordingStart = nil
        LaunchDiagnostics.mark(
            "recording_replacement_started previous_task_id=\(taskID.uuidString.prefix(8)) purpose=\(request.purpose.logName)"
        )
        startRecording(
            instructions: request.instructions,
            activation: request.activation,
            channel: request.channel,
            purpose: request.purpose,
            captureSource: request.captureSource
        )
    }

    private func cancelRecordingStopHandoff(reason: String) {
        pendingRecordingStart = nil
        guard let taskID = recordingStopHandoff.taskID else { return }
        recordingStopHandoff.reset()
        LaunchDiagnostics.mark(
            "recording_stop_handoff phase=cancelled task_id=\(taskID.uuidString.prefix(8)) reason=\(reason)"
        )
    }

    private func openClawRequestInProgress() -> Bool {
        openClawSendInFlight || !pendingOpenClawMessages.isEmpty
    }

    private func finishRecording(reason: String = "manual_or_trigger") {
        cancelAutoFinishTimer()
        guard let session = activeSession else { return }
        let taskID = session.id
        guard recordingStopHandoff.begin(taskID: taskID) else {
            LaunchDiagnostics.mark(
                "recording_finish_duplicate_ignored task_id=\(taskID.uuidString.prefix(8)) reason=\(reason)"
            )
            return
        }
        LaunchDiagnostics.mark(
            "recording_stop_handoff phase=accepted task_id=\(taskID.uuidString.prefix(8)) reason=\(reason)"
        )
        let configuration = session.configuration
        let purpose = session.purpose
        let realtimePreviewTextBeforeStop = session.committedPreviewText + session.latestPreviewText
        let realtimeVoiceDetectedAtFinish = voiceEverDetected
        let targetApp = currentTargetApp(taskID: taskID, fallback: session.targetApp)
        let result: (URL, TimeInterval)?
        do {
            LaunchDiagnostics.mark("recording_finish_requested task_id=\(taskID.uuidString) reason=\(reason)")
            result = try recorder.stop()
            for snapshot in recorder.drainCompletedExperimentalSnapshots() {
                try? FileManager.default.removeItem(at: snapshot.audioURL)
            }
        } catch {
            LaunchDiagnostics.mark("recording_stop_failed task_id=\(taskID.uuidString) error=\(error.localizedDescription)")
            clearActiveRecording()
            cancelActiveWorkflow(reason: "recording_stop_failed")
            inputState = .idle
            controller.setPrimaryStatus("保存录音失败", detail: error.localizedDescription, tone: .error, resetWaveform: true)
            popup.show(state: "保存失败", draft: "")
            completeRecordingStopHandoff(taskID: taskID, outcome: "stop_failed")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainRealtimePreviewForFinalDelivery(taskID: taskID)
            if let (url, _) = result {
                await self.finalizeRealtimePreviewTailIfNeeded(
                    session: session,
                    audioURL: url
                )
            }
            guard self.activeSession?.id == taskID else {
                LaunchDiagnostics.mark(
                    "recording_finish_aborted task_id=\(taskID.uuidString.prefix(8)) reason=session_cancelled_during_stop_tail"
                )
                self.cancelRecordingStopHandoff(reason: "session_cancelled_during_stop_tail")
                return
            }
            let realtimePreviewTextAtFinish = self.realtimePreviewTextForActiveSession(taskID: taskID)
                ?? realtimePreviewTextBeforeStop
            self.prepareShadowPreviewForFinalDelivery(recordingDuration: result?.1)
            let candidateSnapshots = await self.finishShadowPreviewForFinalDelivery(
                languageMode: configuration.languageMode
            )
            guard self.activeSession?.id == taskID else {
                LaunchDiagnostics.mark(
                    "recording_finish_aborted task_id=\(taskID.uuidString.prefix(8)) reason=session_cancelled_during_candidate_capture"
                )
                self.cancelRecordingStopHandoff(reason: "session_cancelled_during_candidate_capture")
                return
            }
            self.clearActiveRecording()
            guard let (url, duration) = result else {
                self.experimentalPreviewPipeline?.cancelPending()
                self.experimentalPreviewPipeline = nil
                self.longFormTranscriptionSession = nil
                LaunchDiagnostics.mark("recording_finish_empty task_id=\(taskID.uuidString)")
                self.workflowState.finishTask(taskID)
                self.inputState = .idle
                self.drainPendingPasteResultsIfPossible()
                self.showEmptyRecording()
                self.releaseASRResourcesIfMemoryElevated()
                self.completeRecordingStopHandoff(taskID: taskID, outcome: "empty")
                return
            }
            LaunchDiagnostics.mark(
                "recording_finish_saved task_id=\(taskID.uuidString) duration_ms=\(Int(duration * 1000)) url=\(url.lastPathComponent)"
            )
            self.discardPendingRealtimeSnapshot()
            let task = RecordingTask(
                id: taskID,
                audioURL: url,
                targetApp: targetApp,
                configuration: configuration,
                purpose: purpose,
                duration: duration,
                finishRequestedAt: Date(),
                reRecognizeWholeRecordingAfterStop: session.reRecognizeWholeRecordingAfterStop,
                realtimePreviewTextAtFinish: realtimePreviewTextAtFinish
            )
            self.inputState = .finalizing(task)
            self.workflowState.submitFinalTask(taskID)
            self.drainPendingPasteResultsIfPossible()
            self.controller.setPrimaryStatus(
                "正在检测人声",
                detail: String(format: "已完整录制 %.1f 秒", duration),
                tone: .processing,
                resetWaveform: true
            )
            if purpose == .openClawChat {
                self.popup.hideAnimated()
            } else {
                self.popup.show(state: "检测中")
            }
            let vadStart = Date()
            self.vadBridge.containsSpeech(audio: url) { [weak self] response in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let vadMs = Int(Date().timeIntervalSince(vadStart) * 1000)
                    let resultText: String
                    switch response {
                    case .failure(let e): resultText = "error(\(e.localizedDescription))"
                    case .success(let v): resultText = v ? "speech" : "no_speech"
                    }
                    LaunchDiagnostics.mark("vad_final task_id=\(taskID.uuidString.prefix(8)) ms=\(vadMs) result=\(resultText)")
                    let shouldUpdateInterface = self.shouldUpdateInterface(for: taskID)
                    switch response {
                    case .failure(let error):
                        LaunchDiagnostics.mark(
                            "vad_final_unavailable_run_asr task_id=\(taskID.uuidString.prefix(8)) error=\(error.localizedDescription)"
                        )
                        if shouldUpdateInterface {
                            self.controller.setPrimaryStatus(
                                "正在识别",
                                detail: "人声检测未完成，改用完整录音识别",
                                tone: .processing,
                                resetWaveform: true
                            )
                            if task.purpose != .openClawChat {
                                self.popup.show(state: "识别中", draft: "")
                            }
                        }
                        self.startFinalRecognition(
                            task,
                            duration: duration,
                            shouldUpdateInterface: shouldUpdateInterface,
                            candidateSnapshots: candidateSnapshots
                        )
                    case .success(false):
                        let shouldRunFinalASR = FinalSpeechGate.shouldRunFinalASR(
                            finalVADDetectedSpeech: false,
                            realtimeVoiceDetected: realtimeVoiceDetectedAtFinish,
                            realtimePreviewText: realtimePreviewTextAtFinish
                        )
                        if shouldRunFinalASR {
                            LaunchDiagnostics.mark(
                                "vad_final_override task_id=\(taskID.uuidString.prefix(8)) reason=realtime_evidence preview_chars=\(realtimePreviewTextAtFinish.count) realtime_voice=\(realtimeVoiceDetectedAtFinish)"
                            )
                            self.startFinalRecognition(
                                task,
                                duration: duration,
                                shouldUpdateInterface: shouldUpdateInterface,
                                candidateSnapshots: candidateSnapshots
                            )
                        } else {
                            if shouldUpdateInterface {
                                self.showEmptyRecording()
                            }
                            self.finishFinalTask(task)
                        }
                    case .success(true):
                        self.startFinalRecognition(
                            task,
                            duration: duration,
                            shouldUpdateInterface: shouldUpdateInterface,
                            candidateSnapshots: candidateSnapshots
                        )
                    }
                }
            }
            self.completeRecordingStopHandoff(taskID: taskID, outcome: "submitted")
        }
    }

    private func startFinalRecognition(
        _ task: RecordingTask,
        duration: TimeInterval,
        shouldUpdateInterface: Bool,
        candidateSnapshots: FinalDeliveryCandidateSnapshots
    ) {
        if shouldUpdateInterface {
            controller.setPrimaryStatus(
                "正在识别",
                detail: String(format: "已完整录制 %.1f 秒", duration),
                tone: .processing,
                resetWaveform: true
            )
            if task.purpose != .openClawChat {
                popup.show(state: "识别中", draft: "")
            }
        }
        let request = FinalRecognitionRequest(
            taskID: task.id,
            audioURL: task.audioURL,
            configuration: task.configuration,
            audioDuration: task.duration,
            reRecognizeWholeRecordingAfterStop: task.reRecognizeWholeRecordingAfterStop
        )
        // 候选快照在旧录音释放 activeSession 前已经按 task 捕获；这里绝不再读取
        // 当前录音的全局 preview runtime，避免快速开启下一句时交叉收尾。
        let selectedForLog = CandidateDeliverySnapshot.selectForFinalDelivery(
            shadowRuntimeSnapshot: candidateSnapshots.shadow,
            realtimePreviewDeliverySnapshot: candidateSnapshots.realtimePreviewDelivery,
            languageMode: task.configuration.languageMode
        )
        let deliverableForLog = selectedForLog?.isDeliverable(languageMode: task.configuration.languageMode) ?? false
        LaunchDiagnostics.mark(
            "candidate_delivery_cache task_id=\(task.id.uuidString.prefix(8)) chars=\(selectedForLog?.text.count ?? 0) source=\(selectedForLog?.source.rawValue ?? "none") usable=\(selectedForLog?.isUsable(languageMode: task.configuration.languageMode) ?? false) deliverable=\(deliverableForLog) lifecycle=\(String(describing: selectedForLog?.lifecycle))"
        )
        finalDeliveryUseCase.deliver(
            taskID: request.taskID,
            audioURL: request.audioURL,
            configuration: request.configuration,
            audioDuration: request.audioDuration,
            shadowRuntimeSnapshot: candidateSnapshots.shadow,
            realtimePreviewDeliverySnapshot: candidateSnapshots.realtimePreviewDelivery,
            reRecognizeWholeRecordingAfterStop: request.reRecognizeWholeRecordingAfterStop
        ) { [weak self] outcome in
            LaunchDiagnostics.markAsync(
                "final_delivery_selected task_id=\(task.id.uuidString.prefix(8)) chars=\(outcome.text.count) source=\(outcome.source) reason=\(outcome.reason)"
            )
            let recognitionOutcome: FinalRecognitionOutcome
            if outcome.source == "final-asr-failed" {
                recognitionOutcome = .failed(outcome.reason)
            } else if outcome.text.isEmpty {
                recognitionOutcome = .empty(FinalRecognitionResult(
                    text: outcome.text,
                    recognitionSeconds: outcome.recognitionSeconds,
                    engine: outcome.source
                ))
            } else {
                recognitionOutcome = .recognized(FinalRecognitionResult(
                    text: outcome.text,
                    recognitionSeconds: outcome.recognitionSeconds,
                    engine: outcome.source
                ))
            }
            DispatchQueue.main.async { self?.handle(recognitionOutcome, task: task) }
        }
    }

    private func beginProductionPreview(taskID: UUID, deliversText: Bool) {
        endProductionPreview(cancelled: true)
        let trace = realtimeTranscriptTrace
        productionRealtimePreviewDeliveryCache.reset(completionObserver: { snapshot in
            trace?.recordFinalCache(text: snapshot.deliveryText)
        })
        let sessionID = TranscriptionSessionID(rawValue: taskID)
        let productionStates = productionPreviewStateBridge.begin(sessionID: sessionID)
        productionPreviewTextCoordinator.begin(
            states: productionStates,
            deliversText: deliversText
        )
    }

    private func beginShadowPreview(taskID: UUID) {
        endShadowPreview(cancelled: true)
        let sessionID = TranscriptionSessionID(rawValue: taskID)
        guard ShadowPreviewRuntimeGate.shouldStart(isEnabled: controller.shadowPreviewEnabled) else { return }

        let runtime: ShadowTranscriptionRuntime
        senseVoiceShadowProvider = nil
        mimoShadowProvider = nil
        onlineShadowProviderName = nil
        onlineShadowSessionShortID = nil
        if ProcessInfo.processInfo.arguments.contains("--debug-shadow-sensevoice") {
            runtime = makeLocalSenseVoiceShadowRuntime(
                sessionID: sessionID,
                taskID: taskID,
                source: "forced_debug"
            )
        } else if ProcessInfo.processInfo.arguments.contains("--debug-shadow-fake-stream") {
            runtime = ShadowTranscriptionRuntime(
                sessionID: sessionID,
                provider: FakeStreamingProvider(
                    id: "installed-shadow-fixture",
                    script: Self.fakeStreamingShadowScript,
                    defaultDelayNanoseconds: 400_000_000
                )
            )
            LaunchDiagnostics.mark(
                "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=fake_stream"
            )
        } else {
            let onlineSettings = OnlineASRSettingsStore().load()
            var createdMiMoProvider: MiMoSnapshotProvider?
            let factory = OnlineASRProviderFactory(
                credentials: OnlineASRCredentialStore(),
                doubaoBuilder: { key in
                    OnlineTranscriptionProvider(
                        id: "doubao-asr",
                        transport: DoubaoStreamingTransport(apiKey: key)
                    )
                },
                mimoBuilder: { key in
                    let provider = MiMoSnapshotProvider(apiKey: key)
                    createdMiMoProvider = provider
                    return provider
                }
            )
            switch factory.make(selection: onlineSettings.selection) {
            case .ready(let provider):
                mimoShadowProvider = createdMiMoProvider
                onlineShadowProviderName = onlineSettings.selection.rawValue
                onlineShadowSessionShortID = String(taskID.uuidString.prefix(8))
                runtime = ShadowTranscriptionRuntime(sessionID: sessionID, provider: provider)
                LaunchDiagnostics.mark(
                    "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=\(onlineSettings.selection.rawValue)"
                )
            case .unavailable(.missingCredential):
                runtime = makeLocalSenseVoiceShadowRuntime(
                    sessionID: sessionID,
                    taskID: taskID,
                    source: "missing_credential_fallback"
                )
                controller.detail.stringValue = "\(onlineSettings.selection.displayName) 未配置 Key；本轮继续使用本地旁路。"
            case .disabled:
                runtime = makeLocalSenseVoiceShadowRuntime(
                    sessionID: sessionID,
                    taskID: taskID,
                    source: "local_fallback"
                )
            }
        }
        shadowPreviewRuntime = runtime
        shadowPreviewStartTask = Task { @MainActor [weak self] in
            do {
                try await runtime.start()
                if await runtime.consumesAudioFrames(), let self {
                    self.beginShadowAudioFrameDelivery(runtime: runtime, taskID: taskID)
                }
                let technicalStates = await runtime.states(
                    visibleCharacterLimit: ShadowTranscriptionRuntime.technicalVisibleCharacterLimit
                )
                guard let self,
                      self.activeSession?.id == taskID,
                      self.shadowPreviewRuntime != nil else { return }
                self.shadowPreviewCoordinator.begin(
                    states: technicalStates,
                    productionFrame: { [weak self] in self?.popup.presentationFrame }
                )
            } catch {
                guard let self, self.activeSession?.id == taskID else { return }
                LaunchDiagnostics.mark(
                    "shadow_preview_start_failed task_id=\(taskID.uuidString.prefix(8)) error=\(error.localizedDescription)"
                )
                self.endShadowPreview(cancelled: true)
            }
        }
    }

    private func makeLocalSenseVoiceShadowRuntime(
        sessionID: TranscriptionSessionID,
        taskID: UUID,
        source: String
    ) -> ShadowTranscriptionRuntime {
        guard let configuration = activeSession?.configuration else {
            LaunchDiagnostics.mark(
                "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=legacy_adapter reason=missing_local_configuration"
            )
            return ShadowTranscriptionRuntime(sessionID: sessionID)
        }
        let provider = SenseVoiceSnapshotProvider(
            recognizer: SenseVoiceSnapshotNativeRecognizer(
                bridge: shadowASR,
                configuration: configuration
            ),
            admission: ClosureSenseVoiceShadowResourceAdmission { [weak self] in
                await self?.canAdmitSenseVoiceShadowRecognition() ?? false
            }
        )
        senseVoiceShadowProvider = provider
        LaunchDiagnostics.mark(
            "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=sensevoice_snapshot source=\(source)"
        )
        return ShadowTranscriptionRuntime(sessionID: sessionID, provider: provider)
    }

    private func publishShadowPreview(
        _ snapshot: PreviewDisplaySnapshot,
        completeTranscript: CompleteTranscriptSnapshot,
        taskID: UUID
    ) {
        let hasRuntime = shadowPreviewRuntime != nil
        guard activeSession?.id == taskID,
              ShadowPreviewRuntimeGate.shouldPublish(
                isEnabled: controller.shadowPreviewEnabled,
                hasRuntime: hasRuntime
              ),
              let runtime = shadowPreviewRuntime else { return }
        let previous = shadowPreviewEventTask
        shadowPreviewEventTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await runtime.consume(snapshot, completeTranscript: completeTranscript)
        }
    }

    private func canAdmitSenseVoiceShadowRecognition() -> Bool {
        if !recorder.isRecording {
            return true
        }
        guard !realtimeBusy,
              pendingRealtimeSnapshot == nil,
              pendingFinalSnapshots.isEmpty,
              let completedAt = lastProductionPreviewCompletedAt else {
            return false
        }
        return ProcessInfo.processInfo.systemUptime - completedAt <= 0.2
    }

    private func beginShadowAudioFrameDelivery(
        runtime: ShadowTranscriptionRuntime,
        taskID: UUID
    ) {
        shadowAudioFrameTask?.cancel()
        if let shadowAudioFrameSubscriptionID {
            recorder.unsubscribeFromAudioFrames(shadowAudioFrameSubscriptionID)
        }
        let subscription = recorder.subscribeToAudioFrames(capacity: 8)
        shadowAudioFrameSubscriptionID = subscription.id
        shadowAudioFrameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in subscription.events {
                guard !Task.isCancelled,
                      self.activeSession?.id == taskID,
                      self.shadowPreviewRuntime != nil else { return }
                switch event {
                case .frame(let frame):
                    do {
                        try await runtime.append(frame)
                    } catch TranscriptionSessionError.terminal {
                        return
                    } catch {
                        LaunchDiagnostics.mark(
                            "shadow_audio_delivery_failed task_id=\(taskID.uuidString.prefix(8)) error=\(error.localizedDescription)"
                        )
                        self.endShadowPreview(cancelled: true)
                        return
                    }
                case .overflow(let droppedFrames):
                    LaunchDiagnostics.mark(
                        "shadow_audio_overflow task_id=\(taskID.uuidString.prefix(8)) dropped_frames=\(droppedFrames)"
                    )
                    self.endShadowPreview(cancelled: true)
                    return
                }
            }
        }
    }

    private func prepareShadowPreviewForFinalDelivery(recordingDuration: TimeInterval? = nil) {
        shadowPreviewStartTask?.cancel()
        shadowPreviewStartTask = nil
        shadowPreviewEventTask?.cancel()
        shadowPreviewEventTask = nil
        shadowPreviewCoordinator.end()
        prepareProductionPreviewForFinalDelivery(recordingDuration: recordingDuration)
    }

    private func prepareProductionPreviewForFinalDelivery(recordingDuration: TimeInterval? = nil) {
        productionRealtimePreviewDeliveryCache.complete(recordingDurationSeconds: recordingDuration)
        productionPreviewStateBridge.complete()
        productionPreviewTextCoordinator.end()
    }

    private func finishShadowPreviewForFinalDelivery(
        languageMode: RecognitionLanguageMode
    ) async -> FinalDeliveryCandidateSnapshots {
        let runtime = shadowPreviewRuntime
        let senseVoiceProvider = senseVoiceShadowProvider
        let mimoProvider = mimoShadowProvider
        let onlineProviderName = onlineShadowProviderName
        let onlineSessionShortID = onlineShadowSessionShortID
        let hadRuntime = runtime != nil
        let hadAudioSubscription = shadowAudioFrameSubscriptionID != nil
        LaunchDiagnostics.mark(
            "shadow_preview_teardown cancelled=false had_runtime=\(hadRuntime) had_audio_subscription=\(hadAudioSubscription)"
        )
        await drainShadowAudioFrameDeliveryForFinalDelivery()
        shadowPreviewRuntime = nil
        senseVoiceShadowProvider = nil
        mimoShadowProvider = nil
        onlineShadowProviderName = nil
        onlineShadowSessionShortID = nil

        let shadowRuntimeSnapshot = await runtime?.completeForDelivery()
        let realtimePreviewDeliverySnapshot = productionRealtimePreviewDeliveryCache.deliverySnapshot()

        if let senseVoiceProvider {
            let diagnostics = await senseVoiceProvider.diagnostics()
            let seamConfidence = diagnostics.latestSeamConfidence.map { String(describing: $0) } ?? "none"
            LaunchDiagnostics.markAsync(
                "shadow_sensevoice_summary accepted_frames=\(diagnostics.acceptedAudioFrames) max_buffered_samples=\(diagnostics.maximumBufferedSamples) max_fast_pending=\(diagnostics.maximumPendingFast) max_correction_pending=\(diagnostics.maximumPendingCorrections) discarded_fast=\(diagnostics.discardedFastRequestCount) discarded_correction=\(diagnostics.discardedCorrectionRequestCount) correction_degraded=\(diagnostics.correctionDegradedCount) resource_degraded=\(diagnostics.resourceDegradedCount) admission_skipped=\(diagnostics.admissionSkippedCount) boundary_correction_requested=\(diagnostics.boundaryCorrectionRequestedCount) boundary_correction_succeeded=\(diagnostics.boundaryCorrectionSucceededCount) boundary_correction_failed=\(diagnostics.boundaryCorrectionFailedCount) seam_confidence=\(seamConfidence) max_concurrent=\(diagnostics.maximumConcurrentRecognitions) completed=\(diagnostics.completedRecognitions) provider_service_ms=\(diagnostics.maximumProviderServiceMilliseconds) audio_duration_ms=\(diagnostics.audioDurationMilliseconds) last_audio_end_ms=\(diagnostics.lastRecognizedAudioEndMilliseconds) tail_gap_ms=\(diagnostics.tailGapMilliseconds)"
            )
        }
        if let onlineProviderName, let onlineSessionShortID {
            let mimoDiagnostics = await mimoProvider?.diagnosticsSnapshot()
            LaunchDiagnostics.markAsync(
                "shadow_online_summary provider=\(onlineProviderName) session=\(onlineSessionShortID) connect_ms=-1 first_text_ms=-1 completed_requests=\(mimoDiagnostics?.completedRequests ?? 0) max_pending=\(mimoDiagnostics?.maximumPendingSnapshots ?? 0) sent_audio_ms=-1 status_code=0 sanitized_request_id=\(onlineSessionShortID) terminal_reason=completed"
            )
        }
        return (shadow: shadowRuntimeSnapshot, realtimePreviewDelivery: realtimePreviewDeliverySnapshot)
    }

    private func drainShadowAudioFrameDeliveryForFinalDelivery(
        timeoutNanoseconds: UInt64 = 500_000_000
    ) async {
        guard let task = shadowAudioFrameTask else {
            shadowAudioFrameSubscriptionID = nil
            return
        }
        let drained = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !drained {
            task.cancel()
            if let shadowAudioFrameSubscriptionID {
                recorder.unsubscribeFromAudioFrames(shadowAudioFrameSubscriptionID)
            }
        }
        shadowAudioFrameTask = nil
        shadowAudioFrameSubscriptionID = nil
    }

    private static let fakeStreamingShadowScript: [FakeStreamingScriptStep] = [
        .init(emission: .partial(segmentID: "fake-0", revision: 1, text: "今")),
        .init(emission: .partial(segmentID: "fake-0", revision: 2, text: "今天")),
        .init(emission: .partial(segmentID: "fake-0", revision: 3, text: "今天讨论")),
        .init(emission: .finalized(TranscriptSegment(
            id: "fake-0",
            text: "今天讨论",
            audioRange: TranscriptionAudioRange(start: 0, end: 1)
        ))),
        .init(emission: .partial(segmentID: "fake-1", revision: 1, text: "在线模型")),
        .init(emission: .connectionChanged(.reconnecting(attempt: 1))),
        .init(
            emission: .partial(segmentID: "fake-stale", revision: 1, text: "旧代次"),
            providerEpochOffset: -1
        ),
        .init(emission: .partial(segmentID: "fake-1", revision: 2, text: "在线模型支持流式输出")),
        .init(emission: .connectionChanged(.connected)),
        .init(emission: .completed),
    ]

    private func endProductionPreview(cancelled: Bool) {
        if cancelled {
            productionPreviewStateBridge.cancel()
        } else {
            productionPreviewStateBridge.complete()
        }
        productionPreviewTextCoordinator.end()
    }

    private func endShadowPreview(cancelled: Bool) {
        let hadRuntime = shadowPreviewRuntime != nil
        let hadAudioSubscription = shadowAudioFrameSubscriptionID != nil
        LaunchDiagnostics.mark(
            "shadow_preview_teardown cancelled=\(cancelled) had_runtime=\(hadRuntime) had_audio_subscription=\(hadAudioSubscription)"
        )
        shadowPreviewStartTask?.cancel()
        shadowPreviewStartTask = nil
        shadowPreviewEventTask?.cancel()
        shadowPreviewEventTask = nil
        shadowAudioFrameTask?.cancel()
        shadowAudioFrameTask = nil
        if let shadowAudioFrameSubscriptionID {
            recorder.unsubscribeFromAudioFrames(shadowAudioFrameSubscriptionID)
        }
        shadowAudioFrameSubscriptionID = nil
        let runtime = shadowPreviewRuntime
        let senseVoiceProvider = senseVoiceShadowProvider
        let mimoProvider = mimoShadowProvider
        let onlineProviderName = onlineShadowProviderName
        let onlineSessionShortID = onlineShadowSessionShortID
        shadowPreviewRuntime = nil
        senseVoiceShadowProvider = nil
        mimoShadowProvider = nil
        onlineShadowProviderName = nil
        onlineShadowSessionShortID = nil
        shadowPreviewCoordinator.end()
        guard let runtime else { return }
        Task {
            if cancelled {
                await runtime.cancel()
            } else {
                await runtime.complete()
            }
            if let senseVoiceProvider {
                let diagnostics = await senseVoiceProvider.diagnostics()
                let seamConfidence = diagnostics.latestSeamConfidence.map { String(describing: $0) } ?? "none"
                LaunchDiagnostics.markAsync(
                    "shadow_sensevoice_summary accepted_frames=\(diagnostics.acceptedAudioFrames) max_buffered_samples=\(diagnostics.maximumBufferedSamples) max_fast_pending=\(diagnostics.maximumPendingFast) max_correction_pending=\(diagnostics.maximumPendingCorrections) discarded_fast=\(diagnostics.discardedFastRequestCount) discarded_correction=\(diagnostics.discardedCorrectionRequestCount) correction_degraded=\(diagnostics.correctionDegradedCount) resource_degraded=\(diagnostics.resourceDegradedCount) admission_skipped=\(diagnostics.admissionSkippedCount) boundary_correction_requested=\(diagnostics.boundaryCorrectionRequestedCount) boundary_correction_succeeded=\(diagnostics.boundaryCorrectionSucceededCount) boundary_correction_failed=\(diagnostics.boundaryCorrectionFailedCount) seam_confidence=\(seamConfidence) max_concurrent=\(diagnostics.maximumConcurrentRecognitions) completed=\(diagnostics.completedRecognitions) provider_service_ms=\(diagnostics.maximumProviderServiceMilliseconds) audio_duration_ms=\(diagnostics.audioDurationMilliseconds) last_audio_end_ms=\(diagnostics.lastRecognizedAudioEndMilliseconds) tail_gap_ms=\(diagnostics.tailGapMilliseconds)"
                )
            }
            if let onlineProviderName, let onlineSessionShortID {
                let mimoDiagnostics = await mimoProvider?.diagnosticsSnapshot()
                LaunchDiagnostics.markAsync(
                    "shadow_online_summary provider=\(onlineProviderName) session=\(onlineSessionShortID) connect_ms=-1 first_text_ms=-1 completed_requests=\(mimoDiagnostics?.completedRequests ?? 0) max_pending=\(mimoDiagnostics?.maximumPendingSnapshots ?? 0) sent_audio_ms=-1 status_code=0 sanitized_request_id=\(onlineSessionShortID) terminal_reason=\(cancelled ? "cancelled" : "completed")"
                )
            }
        }
    }

    private func clearActiveRecording(
        preserveExperimentalCorrections: Bool = false,
        preserveShadowPreviewForFinalDelivery: Bool = false
    ) {
        if !preserveShadowPreviewForFinalDelivery {
            endShadowPreview(cancelled: true)
            endProductionPreview(cancelled: true)
        }
        cancelAutoFinishTimer()
        cancelInitialSilenceTimer()
        systemMediaPlaybackController.resume()
        outputAudioDucker.restore()
        stopRecordingSafetyTimer()
        stopCapsuleStatusTimer()
        activeSession = nil
        if !preserveExperimentalCorrections {
            experimentalPreviewPipeline?.cancelPending()
            experimentalPreviewPipeline = nil
            longFormTranscriptionSession = nil
        }
        recordingStartedAt = nil
        lastProductionPreviewCompletedAt = nil
        lastCapsuleStatusUpdateAt = nil
        updateCapsuleStatus()
        controller.resetInputBands()
        discardPendingRealtimeSnapshot()
        if !isSystemSleeping {
            startBackgroundHealthTimer()
        }
    }

    private func handleAudioInputRouteEvent(_ event: AudioInputRouteEvent) {
        switch event {
        case .manualDeviceDisconnected(let name):
            AudioInputDevice.saveSelectedUID(AudioInputDevice.systemDefaultUID)
            controller.refreshAudioInputDeviceMenu(selectedUID: AudioInputDevice.systemDefaultUID)
            controller.audioInputStatus.stringValue = "\(name) 已断开，已改为跟随系统"
            LaunchDiagnostics.mark("audio_input_disconnect fallback=system_default")
            switchPrimaryMicrophone(to: AudioInputDevice.systemDefaultUID, disconnectMessage: "\(name) 已断开，已改为跟随系统")
        case .systemDefaultChanged:
            guard currentRecorderInputUID.isEmpty else { return }
            switchPrimaryMicrophone(to: AudioInputDevice.systemDefaultUID)
        }
    }

    private func switchPrimaryMicrophone(to uid: String, disconnectMessage: String? = nil) {
        let devices = AudioInputDeviceProvider.devices()
        let resolution = AudioInputRoutePolicy.resolve(
            selectedUID: uid,
            devices: devices,
            defaultDeviceID: AudioInputDeviceProvider.currentDefaultInputDeviceID(),
            preferBuiltInMicForBluetoothSystemDefault: controller.preferBuiltInMicForBluetoothAudioEnabled
        )

        let resolvedUID: String
        let deviceID: AudioDeviceID?
        let deviceName: String
        switch resolution {
        case .manual(let device):
            resolvedUID = device.uid
            deviceID = device.id
            deviceName = device.name
        case .systemDefault(let device):
            resolvedUID = AudioInputDevice.systemDefaultUID
            deviceID = nil
            deviceName = device.name
        case .preferredBuiltIn(let device, _):
            resolvedUID = AudioInputDevice.systemDefaultUID
            deviceID = device.id
            deviceName = device.name
        case .downgradeToSystemDefault(let device):
            resolvedUID = AudioInputDevice.systemDefaultUID
            deviceID = nil
            deviceName = device.name
            AudioInputDevice.saveSelectedUID(AudioInputDevice.systemDefaultUID)
            controller.refreshAudioInputDeviceMenu(selectedUID: AudioInputDevice.systemDefaultUID)
        case .unavailable:
            controller.audioInputStatus.stringValue = "系统输入不可用"
            if recorder.isRecording {
                controller.setPrimaryStatus("麦克风不可用", detail: "已保留当前录音并停止采集", tone: .error)
                finishRecording(reason: "audio_input_unavailable")
            }
            return
        }

        guard recorder.isRecording else {
            currentRecorderInputUID = resolvedUID
            controller.audioInputStatus.stringValue = "已选择：\(deviceName)"
            return
        }

        let previousUID = currentRecorderInputUID
        let intent = audioInputSwitchGeneration.issue(targetUID: resolvedUID)
        controller.audioInputStatus.stringValue = "正在切换麦克风…"
        recorder.switchInput(to: deviceID, deviceName: deviceName, intent: intent) { [weak self] result in
            guard let self else { return }
            switch result {
            case .switched(let name), .followedSystem(let name, _):
                self.currentRecorderInputUID = resolvedUID
                let message = disconnectMessage ?? "主麦克风已切换到 \(name)"
                self.controller.audioInputStatus.stringValue = message
                ToastPresenter.shared.show(message, style: .success, duration: 1.6)
            case .restoredPrevious(let name, let error):
                AudioInputDevice.saveSelectedUID(previousUID)
                self.controller.refreshAudioInputDeviceMenu(selectedUID: previousUID)
                self.controller.audioInputStatus.stringValue = "切换失败，继续使用：\(name)"
                LaunchDiagnostics.mark("audio_input_switch_failed recovered=true error=\(error)")
                ToastPresenter.shared.show("切换失败，继续使用 \(name)", style: .warning, duration: 2.2)
            case .unavailable(let error):
                self.controller.audioInputStatus.stringValue = "系统输入不可用，录音已停止"
                LaunchDiagnostics.mark("audio_input_switch_failed recovered=false error=\(error)")
                ToastPresenter.shared.show("麦克风不可用，已停止录音", style: .error, duration: 2.6)
                self.finishRecording(reason: "audio_input_switch_unavailable")
            case .superseded:
                break
            }
        }
    }

    @MainActor
    private func drainRealtimePreviewForFinalDelivery(
        taskID: UUID,
        timeoutNanoseconds: UInt64 = 1_200_000_000
    ) async {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var iterations = 0
        while activeSession?.id == taskID,
              (realtimeBusy || pendingRealtimeSnapshot != nil || !pendingFinalSnapshots.isEmpty) {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            if elapsed >= timeoutNanoseconds {
                LaunchDiagnostics.mark(
                    "realtime_stop_drain_timeout task_id=\(taskID.uuidString.prefix(8)) busy=\(realtimeBusy) pending_realtime=\(pendingRealtimeSnapshot != nil) pending_final=\(pendingFinalSnapshots.count)"
                )
                return
            }
            iterations += 1
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        LaunchDiagnostics.mark(
            "realtime_stop_drain_completed task_id=\(taskID.uuidString.prefix(8)) wait_ms=\(elapsed / 1_000_000) iterations=\(iterations)"
        )
    }

    private func realtimePreviewTextForActiveSession(taskID: UUID) -> String? {
        guard let session = activeSession, session.id == taskID else { return nil }
        return session.committedPreviewText + session.latestPreviewText
    }

    @MainActor
    private func finalizeRealtimePreviewTailIfNeeded(
        session: SpeechSession,
        audioURL: URL
    ) async {
        let taskID = session.id
        guard !session.reRecognizeWholeRecordingAfterStop else {
            LaunchDiagnostics.mark(
                "realtime_stop_tail_skipped reason=full_final_asr_enabled task_id=\(taskID.uuidString.prefix(8))"
            )
            return
        }
        guard let pipeline = experimentalPreviewPipeline else {
            LaunchDiagnostics.mark(
                "realtime_stop_tail_skipped reason=pipeline_unavailable task_id=\(taskID.uuidString.prefix(8))"
            )
            return
        }
        let tailSnapshot: ExperimentalPreviewTailSnapshot
        do {
            tailSnapshot = try recorder.makeExperimentalTailSnapshot(
                from: audioURL,
                taskID: taskID
            )
        } catch {
            LaunchDiagnostics.mark(
                "realtime_stop_tail_snapshot_failed task_id=\(taskID.uuidString.prefix(8)) error=\(error.localizedDescription) fallback=current_realtime_cache"
            )
            return
        }
        LaunchDiagnostics.mark(
            "realtime_stop_tail_started task_id=\(taskID.uuidString.prefix(8)) audio_ms=\(Int(tailSnapshot.audioRange.duration * 1_000))"
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.finishWhenCorrectionsDrained(tailSnapshot: tailSnapshot) { state in
                LaunchDiagnostics.mark(
                    "realtime_stop_tail_completed task_id=\(taskID.uuidString.prefix(8)) chars=\(state.displayText.count) recovery=\(state.recoveryRequested)"
                )
                continuation.resume()
            }
        }
    }

    private func discardPendingRealtimeSnapshot() {
        pendingRealtimeSnapshot = nil
        pendingFinalSnapshots.removeAll()
        realtimeBusy = false
        activeRealtimeSnapshotID = nil
        realtimeSnapshotTimeoutWorkItem?.cancel()
        realtimeSnapshotTimeoutWorkItem = nil
    }

    private func receiveRealtimeSnapshot(
        taskID: UUID,
        samples: [Float],
        sampleRate: Int,
        chunkIndex: Int,
        isChunkFinal: Bool,
        audioDuration: TimeInterval,
        audioRange: PreviewAudioRange
    ) {
        guard let session = activeSession,
              workflowState.canAcceptRealtimeCallback(taskID: taskID, activeSessionID: session.id) else {
            return
        }
        let request = RealtimeSnapshotRequest(
            taskID: taskID,
            samples: samples,
            sampleRate: sampleRate,
            configuration: session.configuration,
            chunkIndex: chunkIndex,
            isChunkFinal: isChunkFinal,
            audioDuration: audioDuration,
            audioRange: audioRange,
            audioCoverageSeconds: recordingStartedAt.map { Date().timeIntervalSince($0) } ?? audioDuration
        )
        if session.experimentalPreviewSettings.correctedPreviewEnabled {
            experimentalPreviewPipeline?.receiveFast(request)
            return
        }
        if realtimeBusy {
            if isChunkFinal {
                // 块最终快照绝不丢弃，进专用队列。
                pendingFinalSnapshots.append(request)
            } else {
                // 普通中间快照只保留最新一帧（合并旧的）。
                pendingRealtimeSnapshot = request
            }
            return
        }
        transcribeRealtime(request)
    }

    private func receiveExperimentalCorrectionSnapshot(_ snapshot: ExperimentalPreviewAudioSnapshot) {
        guard let session = activeSession,
              session.id == snapshot.taskID,
              session.experimentalPreviewSettings.correctedPreviewEnabled else {
            try? FileManager.default.removeItem(at: snapshot.audioURL)
            return
        }
        experimentalPreviewPipeline?.receiveCorrection(snapshot)
    }

    private func applyExperimentalPreviewState(_ state: PreviewTranscriptState, taskID: UUID) {
        guard var session = activeSession,
              session.id == taskID,
              session.experimentalPreviewSettings.correctedPreviewEnabled else { return }
        session.committedPreviewText = state.confirmedText
        session.latestPreviewText = state.mutableTailText
        activeSession = session
        if session.experimentalPreviewSettings.longFormIncrementalOutputEnabled {
            let existingIDs = Set(longFormTranscriptionSession?.confirmedSegments.map(\.id) ?? [])
            let newSegments = state.confirmedSegments.filter { !existingIDs.contains($0.id) }
            for segment in newSegments {
                longFormTranscriptionSession?.appendConfirmed(segment)
            }
            if !newSegments.isEmpty {
                let store = incrementalTranscriptStore
                longFormPersistenceQueue.async {
                    for segment in newSegments {
                        do {
                            try store.appendConfirmed(segment, sessionID: taskID)
                        } catch {
                            LaunchDiagnostics.mark(
                                "long_form_store_append_failed task_id=\(taskID.uuidString.prefix(8)) segment_id=\(segment.id.uuidString.prefix(8)) error=\(error.localizedDescription)"
                            )
                        }
                    }
                }
            }
        }
        let display = longFormTranscriptionSession?.capsuleProjection(mutableTail: state.mutableTailText)
            ?? state.displayText
        controller.updateRealtimeDraft(display)
        // 生产胶囊改由 productionPreviewTextCoordinator 订阅统一核心 PreviewViewState 驱动
        // （见 publishShadowPreview 之后的旁路 runtime 消费链路），
        // 不再由本函数直喂 popup.updateDraft(snapshot)。
        let productSnapshot = PreviewDisplaySnapshot(
            revision: state.displayRevision,
            stableCharacterCount: state.confirmedCharacterCount,
            stableWindowText: state.confirmedText,
            volatileTailText: state.mutableTailText.isEmpty ? state.displayText : state.mutableTailText
        )
        let completeTranscript = CompleteTranscriptSnapshot(
            revision: state.displayRevision,
            stableText: state.confirmedText,
            volatileTailText: state.mutableTailText,
            lifecycle: .running,
            sourceIdentity: "experimental-production-preview"
        )
        productionRealtimePreviewDeliveryCache.consume(completeTranscript)
        productionPreviewStateBridge.consume(productSnapshot)
        publishShadowPreview(
            productSnapshot,
            completeTranscript: completeTranscript,
            taskID: taskID
        )
        LaunchDiagnostics.markAsync(
            "experimental_preview_update task_id=\(taskID.uuidString.prefix(8)) revision=\(state.displayRevision) confirmed_chars=\(state.confirmedCharacterCount) visible_chars=\(state.displayText.count) recovery=\(state.recoveryRequested)"
        )
    }

    private func completeLongFormIncrementalFinalization(
        state: PreviewTranscriptState,
        task: RecordingTask,
        duration: TimeInterval
    ) {
        for segment in state.confirmedSegments {
            longFormTranscriptionSession?.appendConfirmed(segment)
        }
        let store = incrementalTranscriptStore
        let authoritativeConfirmedText = state.confirmedText
        let tail = state.mutableTailText
        longFormPersistenceQueue.async { [weak self] in
            for segment in state.confirmedSegments {
                do {
                    try store.appendConfirmed(segment, sessionID: task.id)
                } catch {
                    LaunchDiagnostics.mark(
                        "long_form_store_retry_failed task_id=\(task.id.uuidString.prefix(8)) segment_id=\(segment.id.uuidString.prefix(8)) error=\(error.localizedDescription)"
                    )
                }
            }
            let transcript: String
            do {
                transcript = try store.finalize(
                    sessionID: task.id,
                    authoritativeConfirmedText: authoritativeConfirmedText,
                    tail: tail,
                    degraded: state.recoveryRequested
                )
            } catch {
                transcript = authoritativeConfirmedText + tail
                LaunchDiagnostics.mark(
                    "long_form_store_finalize_failed task_id=\(task.id.uuidString.prefix(8)) error=\(error.localizedDescription)"
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.experimentalPreviewPipeline = nil
                self.longFormTranscriptionSession = nil
                self.longFormFinalizationTaskIDs.remove(task.id)
                guard isMeaningfulRecognitionText(transcript) else {
                    if self.shouldUpdateInterface(for: task.id) { self.showEmptyRecording() }
                    self.finishFinalTask(task)
                    return
                }
                LaunchDiagnostics.mark(
                    "long_form_incremental_final task_id=\(task.id.uuidString.prefix(8)) duration_ms=\(Int(duration * 1000)) chars=\(transcript.count) degraded=\(state.recoveryRequested)"
                )
                self.handle(.recognized(FinalRecognitionResult(
                    text: transcript,
                    recognitionSeconds: 0,
                    engine: "sensevoice-incremental-experimental"
                )), task: task)
            }
        }
    }

    private func transcribeRealtime(_ request: RealtimeSnapshotRequest) {
        let snapshotID = UUID()
        let taskID = request.taskID
        activeRealtimeSnapshotID = snapshotID
        realtimeBusy = true
        if shouldSkipRealtimeASRForSilence(request) {
            LaunchDiagnostics.mark(
                "realtime_snapshot_skipped_silence task_id=\(taskID.uuidString.prefix(8)) chunk=\(request.chunkIndex) final=\(request.isChunkFinal) samples=\(request.samples.count)"
            )
            if request.isChunkFinal {
                applyRealtimePreview(request: request, response: .success([
                    "text": "",
                    "engine": "realtime-silence-gate",
                    "audio_source": "memory_pcm",
                ]))
            }
            finishRealtimeSnapshot(snapshotID: snapshotID)
            return
        }
        scheduleRealtimeSnapshotTimeout(snapshotID: snapshotID, taskID: taskID)
        realtimeASR.transcribe(
            samples: request.samples,
            sampleRate: request.sampleRate,
            configuration: request.configuration
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.activeRealtimeSnapshotID == snapshotID else { return }
                self.applyRealtimePreview(request: request, response: response)
                self.finishRealtimeSnapshot(snapshotID: snapshotID)
            }
        }
    }

    private func shouldSkipRealtimeASRForSilence(
        _ request: RealtimeSnapshotRequest,
        now: Date = Date()
    ) -> Bool {
        guard request.isChunkFinal else { return false }
        guard voiceDetectionAvailable else { return false }
        guard let latestVoiceProbeHasSpeech,
              let latestVoiceProbeCapturedAt else { return false }
        guard now.timeIntervalSince(latestVoiceProbeCapturedAt) <= Timing.realtimeSilenceGateProbeFreshnessSeconds else {
            return false
        }
        if latestVoiceProbeHasSpeech {
            return false
        }
        if let lastVoiceAt,
           now.timeIntervalSince(lastVoiceAt) <= Timing.realtimeSilenceGateVoiceGraceSeconds {
            return false
        }
        return true
    }

    /// 把某个块快照的识别结果合并进预览：committedPreviewText（冻结前缀）+ 当前块尾巴。
    /// 块最终快照会把尾巴冻结进 committedPreviewText，从此不再变动（稳定、不跳变）。
    private func applyRealtimePreview(request: RealtimeSnapshotRequest, response: Result<[String: Any], Error>) {
        guard var session = activeSession,
              workflowState.canAcceptRealtimeCallback(taskID: request.taskID, activeSessionID: session.id) else { return }
        // 已提交块的滞后快照直接丢弃，不污染显示。
        guard request.chunkIndex >= session.currentChunkIndex else { return }

        if case .success(let value) = response, (value["error"] as? String ?? "").isEmpty {
            let text = cleanRecognitionText(value["text"] as? String ?? "", languageMode: request.configuration.languageMode)
            // 尾巴去重/幻觉过滤只跟「本块之前的尾巴」比较；committed 前缀不参与。
            if isMeaningfulRealtimePreviewText(text, previousPreview: session.latestPreviewText) {
                session.latestPreviewText = text
            }
        }
        if request.isChunkFinal {
            // 冻结提交：把当前块尾巴并入前缀，块序号前进，尾巴清空。
            session.committedPreviewText += session.latestPreviewText
            session.currentChunkIndex = request.chunkIndex + 1
            session.latestPreviewText = ""
        }
        activeSession = session

        let display = session.committedPreviewText + session.latestPreviewText
        controller.updateRealtimeDraft(display)
        // 生产胶囊改由 productionPreviewTextCoordinator 订阅统一核心 PreviewViewState 驱动，
        // 不再由本函数直喂 popup.updateDraft(snapshot)。committedPreviewText/latestPreviewText
        // 仍需保留：它们是完整实时缓存与 UI 投影共同读取的生产数据源。
        let productSnapshot = PreviewDisplaySnapshot(
            revision: 0,
            stableCharacterCount: session.committedPreviewText.count,
            stableWindowText: session.committedPreviewText,
            volatileTailText: session.latestPreviewText
        )
        let completeTranscript = CompleteTranscriptSnapshot(
            revision: 0,
            stableText: session.committedPreviewText,
            volatileTailText: session.latestPreviewText,
            lifecycle: .running,
            sourceIdentity: "production-realtime-preview"
        )
        productionRealtimePreviewDeliveryCache.consume(
            completeTranscript,
            audioCoverageSeconds: request.audioCoverageSeconds
        )
        productionPreviewStateBridge.consume(productSnapshot)
        publishShadowPreview(
            productSnapshot,
            completeTranscript: completeTranscript,
            taskID: request.taskID
        )
        let elapsedMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        LaunchDiagnostics.mark(
            "realtime_preview_update task_id=\(request.taskID.uuidString) elapsed_ms=\(elapsedMs) chunk=\(request.chunkIndex) final=\(request.isChunkFinal) chars=\(display.count)"
        )
    }

    private func scheduleRealtimeSnapshotTimeout(snapshotID: UUID, taskID: UUID) {
        realtimeSnapshotTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeRealtimeSnapshotID == snapshotID else { return }
            LaunchDiagnostics.mark(
                "realtime_snapshot_timeout task_id=\(taskID.uuidString) seconds=\(Int(Timing.realtimeSnapshotTimeoutSeconds))"
            )
            self.finishRealtimeSnapshot(snapshotID: snapshotID)
        }
        realtimeSnapshotTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.realtimeSnapshotTimeoutSeconds, execute: workItem)
    }

    private func finishRealtimeSnapshot(snapshotID: UUID? = nil) {
        if let snapshotID, activeRealtimeSnapshotID != snapshotID { return }
        realtimeSnapshotTimeoutWorkItem?.cancel()
        realtimeSnapshotTimeoutWorkItem = nil
        activeRealtimeSnapshotID = nil
        realtimeBusy = false
        // 先处理块最终快照（保证提交、保持顺序），再处理最新的中间快照。
        if !pendingFinalSnapshots.isEmpty {
            dispatchPendingRealtime(pendingFinalSnapshots.removeFirst())
            return
        }
        if let pending = pendingRealtimeSnapshot {
            pendingRealtimeSnapshot = nil
            dispatchPendingRealtime(pending)
        }
        if !realtimeBusy {
            lastProductionPreviewCompletedAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func dispatchPendingRealtime(_ request: RealtimeSnapshotRequest) {
        if workflowState.canAcceptRealtimeCallback(taskID: request.taskID, activeSessionID: activeSession?.id) {
            transcribeRealtime(request)
        }
    }

    private func handle(_ outcome: FinalRecognitionOutcome, task: RecordingTask) {
        let shouldUpdateInterface = shouldUpdateInterface(for: task.id)
        switch outcome {
        case .failed(let message):
            LaunchDiagnostics.mark(
                "final_asr_failed task_id=\(task.id.uuidString) selected_backend=\(task.configuration.backend.rawValue) elapsed_ms=\(Int(max(0, Date().timeIntervalSince(task.finishRequestedAt)) * 1000)) error_chars=\(message.count)"
            )
            if shouldUpdateInterface {
                controller.setPrimaryStatus("识别失败", detail: message, tone: .error, resetWaveform: true)
                if task.purpose == .openClawChat {
                    popup.hideAnimated()
                } else {
                    popup.show(state: "识别失败", draft: "")
                }
            }
            finishFinalTask(task)
        case .recognized(let result):
            let finalSource: String
            if result.engine == "candidate-preview-cache" {
                finalSource = "candidate_preview_cache"
            } else if result.engine == "realtime-preview-delivery-cache" {
                finalSource = "realtime_preview_delivery_cache"
            } else if result.engine == "realtime-preview-cache" {
                finalSource = "realtime_preview_cache"
            } else {
                finalSource = "final_asr"
            }
            LaunchDiagnostics.mark(
                "final_asr_result task_id=\(task.id.uuidString) selected_backend=\(task.configuration.backend.rawValue) source=\(finalSource) audio_duration_ms=\(Int(task.duration * 1000)) recognition_ms=\(Int(result.recognitionSeconds * 1000)) elapsed_ms=\(Int(max(0, Date().timeIntervalSince(task.finishRequestedAt)) * 1000)) chars=\(result.text.count) executed_engine=\(result.engine)"
            )
            guard markFinalTaskForSubmission(task.id) else {
                finishFinalTask(task)
                return
            }
            if task.purpose == .openClawChat {
                if shouldUpdateInterface {
                    controller.updateRealtimeDraft(result.text)
                    controller.setPrimaryStatus(
                        "发送 OpenClaw",
                        detail: "已识别完成，正在发送给 OpenClaw",
                        tone: .processing,
                        resetWaveform: true
                    )
                }
                submitOpenClawRequest(result.text, elapsed: result.recognitionSeconds, task: task)
                return
            }
            if shouldUpdateInterface {
                controller.updateRealtimeDraft(result.text)
                let preference = smartRewritePreference(for: task.purpose)
                let context = SmartInputContext(targetApp: currentTargetApp(for: task))
                let progress = smartInputRouter.progressInfo(preference: preference, context: context)
                if controller.autoTranslateEnabled {
                    if controller.translationDirection.usesRawSourceTextForTranslation {
                        controller.setPrimaryStatus(
                            "AI 翻译中",
                            detail: smartTranslationProgressDetail(
                                direction: controller.translationDirection,
                                modelName: smartEngine.displayName
                            ),
                            tone: .processing,
                            resetWaveform: true
                        )
                        popup.show(state: "翻译中", draft: "")
                    } else if progress.shouldRewrite {
                        controller.setPrimaryStatus(
                            "AI 整理中",
                            detail: "整理后继续\(controller.translationDirection.displayName) · \(smartEngine.displayName)",
                            tone: .processing,
                            resetWaveform: true
                        )
                        popup.show(state: "整理中", draft: "")
                    } else {
                        controller.setPrimaryStatus(
                            "AI 翻译中",
                            detail: smartTranslationProgressDetail(
                                direction: controller.translationDirection,
                                modelName: smartEngine.displayName
                            ),
                            tone: .processing,
                            resetWaveform: true
                        )
                        popup.show(state: "翻译中", draft: "")
                    }
                } else if progress.shouldRewrite {
                    controller.setPrimaryStatus(
                        "AI 整理中",
                        detail: smartRewriteProgressDetail(progress),
                        tone: .processing,
                        resetWaveform: true
                    )
                    popup.show(state: "整理中", draft: "")
                } else {
                    controller.setPrimaryStatus(
                        "识别完成",
                        detail: String(format: "原文模式 · 本地识别耗时 %.2f 秒", result.recognitionSeconds),
                        tone: .success,
                        resetWaveform: true
                    )
                }
            }
            if controller.autoTranslateEnabled && task.purpose == .dictation {
                rewriteTranslateAndSubmit(result.text, elapsed: result.recognitionSeconds, task: task)
            } else {
                rewriteAndSubmit(result.text, elapsed: result.recognitionSeconds, task: task)
            }
        case .empty(let result):
            LaunchDiagnostics.mark(
                "final_asr_empty task_id=\(task.id.uuidString) audio_duration_ms=\(Int(task.duration * 1000)) recognition_ms=\(Int(result.recognitionSeconds * 1000)) chars=\(result.text.count) engine=\(result.engine)"
            )
            if shouldUpdateInterface {
                showEmptyRecording()
            }
            finishFinalTask(task)
        }
    }

    private func rewriteTranslateAndSubmit(_ rawText: String, elapsed: Double, task: RecordingTask) {
        let preference = smartRewritePreference(for: task.purpose)
        let direction = controller.translationDirection
        let context = SmartInputContext(
            targetApp: currentTargetApp(for: task),
            recordingSessionId: task.id.uuidString
        )
        Task { [weak self] in
            guard let self else { return }
            let rewriteResult: SmartRewriteResult
            let sourceForTranslation: String
            if direction.usesRawSourceTextForTranslation {
                let trimmedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                rewriteResult = SmartRewriteResult(
                    text: trimmedRawText,
                    rawText: rawText,
                    mode: .raw,
                    didFallback: false
                )
                sourceForTranslation = trimmedRawText.isEmpty ? rawText : trimmedRawText
            } else {
                rewriteResult = await self.performFinalRewrite(
                    rawText: rawText,
                    preference: preference,
                    context: context
                )
                sourceForTranslation = rewriteResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? rawText
                    : rewriteResult.text
            }
            if rewriteResult.mode != .raw,
               !rewriteResult.didFallback,
               self.shouldUpdateInterface(for: task.id) {
                await MainActor.run {
                    self.controller.setPrimaryStatus(
                        "AI 翻译中",
                        detail: self.smartTranslationProgressDetail(
                            direction: direction,
                            modelName: self.smartEngine.displayName
                        ),
                        tone: .processing,
                        resetWaveform: true
                    )
                    self.popup.show(state: "翻译中", draft: "")
                }
            }
            let translation = await self.translateWithTimeout(
                rawText: sourceForTranslation,
                direction: direction,
                context: context,
                timeoutSeconds: 10.0
            )
            await MainActor.run {
                let finalText = translation?.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? translation?.translatedText ?? sourceForTranslation
                    : sourceForTranslation
                if self.shouldUpdateInterface(for: task.id) {
                    if let translation {
                        self.controller.updateRealtimeDraft("\(sourceForTranslation)\n\(translation.translatedText)")
                        self.controller.setPrimaryStatus(
                            "翻译完成",
                            detail: "已整理并按\(translation.direction.displayName)转换 · \(translation.modelName)",
                            tone: .success,
                            resetWaveform: true
                        )
                    } else {
                        self.controller.updateRealtimeDraft(finalText)
                        self.controller.setPrimaryStatus(
                            "翻译未完成",
                            detail: String(format: "已使用%@文本 · %.2f 秒", rewriteResult.mode == .raw ? "原始识别" : "整理后", elapsed),
                            tone: .warning,
                            resetWaveform: true
                        )
                    }
                    self.popup.hideAnimated()
                }
                self.submitPasteResult(PendingPasteResult(
                    task: task,
                    text: finalText,
                    rawText: rawText,
                    sourceText: translation == nil ? nil : sourceForTranslation,
                    translatedText: translation?.translatedText,
                    translationDirection: translation?.direction,
                    wasTranslationRequested: true,
                    rewriteMode: rewriteResult.mode,
                    usage: translation == nil ? rewriteResult.usage : SmartUsage.combined([rewriteResult.usage, translation?.usage])
                ))
            }
        }
    }

    private func rewriteAndSubmit(_ rawText: String, elapsed: Double, task: RecordingTask) {
        let preference = smartRewritePreference(for: task.purpose)
        let context = SmartInputContext(
            targetApp: currentTargetApp(for: task),
            recordingSessionId: task.id.uuidString
        )
        Task { [weak self] in
            guard let self else { return }
            let result = await self.performFinalRewrite(
                rawText: rawText,
                preference: preference,
                context: context
            )
            await MainActor.run {
                let finalText = result.text.isEmpty ? rawText : result.text
                if self.shouldUpdateInterface(for: task.id) {
                    self.controller.updateRealtimeDraft(finalText)
                    self.controller.setPrimaryStatus(
                        "识别完成",
                        detail: self.smartRewriteDetail(result: result, elapsed: elapsed),
                        tone: .success,
                        resetWaveform: true
                    )
                    self.popup.hideAnimated()
                }
                self.submitPasteResult(PendingPasteResult(
                    task: task,
                    text: finalText,
                    rawText: rawText,
                    sourceText: nil,
                    translatedText: nil,
                    translationDirection: nil,
                    wasTranslationRequested: false,
                    rewriteMode: result.mode,
                    usage: result.usage
                ))
            }
        }
    }

    private func submitOpenClawRequest(_ rawText: String, elapsed: Double, task: RecordingTask) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if shouldUpdateInterface(for: task.id) {
                showEmptyRecording()
            }
            finishFinalTask(task)
            return
        }
        let settings = controller.openClawSettings
        LaunchDiagnostics.mark(
            "openclaw_send_start task_id=\(task.id.uuidString.prefix(8)) chars=\(trimmed.count) agent=\(settings.agentID) session=\(settings.sessionKey)"
        )
        enqueueOpenClawMessage(PendingOpenClawMessage(
            turnID: UUID(),
            text: trimmed,
            elapsed: elapsed,
            task: task,
            settings: settings
        ))
        finishFinalTask(task)
    }

    private func enqueueOpenClawMessage(_ message: PendingOpenClawMessage) {
        let wasBusy = openClawSendInFlight || !pendingOpenClawMessages.isEmpty
        pendingOpenClawMessages.append(message)
        OpenClawReplyPresenter.shared.showUserMessage(message.text, turnID: message.turnID)
        if wasBusy {
            OpenClawReplyPresenter.shared.showStatusMessage("已排队，等待 OpenClaw 回复…", turnID: message.turnID)
            if !recorder.isRecording {
                controller.setPrimaryStatus(
                    "OpenClaw 已排队",
                    detail: "上一条还在回复，本条会自动发送",
                    tone: .processing,
                    resetWaveform: true
                )
            }
        }
        drainNextOpenClawMessageIfNeeded()
    }

    private func drainNextOpenClawMessageIfNeeded() {
        guard !openClawSendInFlight, !pendingOpenClawMessages.isEmpty else { return }
        let message = pendingOpenClawMessages.removeFirst()
        openClawSendInFlight = true
        OpenClawReplyPresenter.shared.showReplyLoading(turnID: message.turnID)
        OpenClawVoicePlayer.shared.prewarm()
        if !recorder.isRecording {
            controller.setPrimaryStatus(
                "发送 OpenClaw",
                detail: "正在发送给 OpenClaw",
                tone: .processing,
                resetWaveform: true
            )
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.openClawClient.send(message: message.text, settings: message.settings)
                await MainActor.run {
                    let display = "我：\(message.text)\nOpenClaw：\(response.replyText)"
                    self.controller.addRecentTranscription(
                        display,
                        recognitionSeconds: max(0, Date().timeIntervalSince(message.task.finishRequestedAt)),
                        sourceText: nil,
                        translatedText: nil,
                        translationDirection: nil,
                        usage: nil
                    )
                    if !self.recorder.isRecording {
                        self.controller.updateRealtimeDraft(display)
                        self.controller.setPrimaryStatus(
                            "OpenClaw 已回复",
                            detail: String(format: "本地识别 %.2f 秒 · 已保存到最近转录", message.elapsed),
                            tone: .success,
                            resetWaveform: true
                        )
                    }
                    OpenClawReplyPresenter.shared.showReplySequence(
                        displayEvents: response.displayEvents.map(\.text),
                        reply: response.replyText,
                        turnID: message.turnID
                    )
                    OpenClawVoicePlayer.shared.speak(response.replyText)
                    LaunchDiagnostics.mark(
                        "openclaw_send_done task_id=\(message.task.id.uuidString.prefix(8)) reply_chars=\(response.replyText.count)"
                    )
                    self.openClawSendInFlight = false
                    self.drainNextOpenClawMessageIfNeeded()
                }
            } catch {
                await MainActor.run {
                    let errorMessage = error.localizedDescription
                    self.controller.addRecentTranscription(
                        "OpenClaw 发送失败：\(message.text)",
                        recognitionSeconds: max(0, Date().timeIntervalSince(message.task.finishRequestedAt))
                    )
                    if !self.recorder.isRecording {
                        self.controller.updateRealtimeDraft(message.text)
                        self.controller.setPrimaryStatus(
                            "OpenClaw 发送失败",
                            detail: errorMessage,
                            tone: .error,
                            resetWaveform: true
                        )
                    }
                    OpenClawReplyPresenter.shared.showStatusMessage("OpenClaw 发送失败：\(errorMessage)", turnID: message.turnID)
                    LaunchDiagnostics.mark(
                        "openclaw_send_failed task_id=\(message.task.id.uuidString.prefix(8)) error=\"\(errorMessage)\""
                    )
                    self.openClawSendInFlight = false
                    self.drainNextOpenClawMessageIfNeeded()
                }
            }
        }
    }

    private func smartRewritePreference(for purpose: SpeechInputPurpose) -> SmartRewritePreference {
        switch purpose {
        case .dictation:
            return controller.smartRewritePreference
        case .ideaPill:
            return IdeaPillRewriteModeStore.load()
        case .openClawChat:
            return .raw
        }
    }

    private func smartRewriteDetail(result: SmartRewriteResult, elapsed: Double) -> String {
        if let reason = result.fallbackReason {
            return reason
        }
        if result.didFallback {
            return String(format: "智能整理未完成，已使用原始识别文本 · %.2f 秒", elapsed)
        }
        switch result.mode {
        case .raw:
            return String(format: "原文模式 · 本地识别耗时 %.2f 秒", elapsed)
        case .polish, .developerRequirement, .developerStatement, .codeCommit, .note, .chat, .exhaustiveSummary:
            let model = result.modelName.map { " · \($0)" } ?? ""
            return "已按\(result.mode.displayName)模式整理\(model)，准备粘贴"
        case .command:
            return "命令模式未执行操作，已按原文准备粘贴"
        }
    }

    private func smartRewriteProgressDetail(_ progress: SmartRewriteProgressInfo) -> String {
        let seconds = Int(progress.timeoutSeconds.rounded())
        return "正在用\(progress.modelName)进行\(progress.mode.displayName)，最多等待 \(seconds) 秒"
    }

    private func smartTranslationProgressDetail(
        direction: SmartTranslationDirection,
        modelName: String
    ) -> String {
        "正在用\(modelName)进行\(direction.displayName)，历史会保留原文和译文"
    }

    private func performFinalRewrite(
        rawText: String,
        preference: SmartRewritePreference,
        context: SmartInputContext
    ) async -> SmartRewriteResult {
        isFinalRewriteInFlight = true
        defer { isFinalRewriteInFlight = false }
        return await smartInputRouter.rewrite(
            rawText: rawText,
            preference: preference,
            context: context
        )
    }

    private func translateWithTimeout(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        timeoutSeconds: TimeInterval
    ) async -> SmartTranslationOutput? {
        isTranslationInFlight = true
        defer { isTranslationInFlight = false }
        let usesManagedRuntime = SmartAIModelStore.load().provider == .typeWhaleMLX
        // 超时只放弃等待、不取消请求，让翻译后台跑完并把已计费的 usage 补记进账本，避免漏记与绕过成本上限。
        // 本地直驱无外部计费；超时必须取消 owned helper 的当前请求，避免旧结果晚到。
        let work = Task {
            try await self.smartEngine.translate(
                rawText: rawText,
                direction: direction,
                context: context
            )
        }
        do {
            return try await withThrowingTaskGroup(of: SmartTranslationOutput.self) { group in
                group.addTask { try await work.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw SmartRewriteError.timeout
                }
                do {
                    let value = try await group.next()
                    group.cancelAll()
                    return value
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } catch {
            if usesManagedRuntime {
                work.cancel()
                cancelActiveSmartAIWork(reason: "voice_translation_timeout")
                return nil
            }
            Task {
                if let late = try? await work.value {
                    SmartUsageLedgerStore.record(late.usage)
                }
            }
            return nil
        }
    }

    private func submitPasteResult(_ result: PendingPasteResult) {
        guard workflowState.canSubmitProcessedResult(taskID: result.task.id) else {
            SmartUsageLedgerStore.record(result.usage)
            LaunchDiagnostics.mark("paste_result_ignored_stale task_id=\(result.task.id.uuidString)")
            finishFinalTask(result.task)
            return
        }
        addRecentTranscription(for: result, completedAt: Date())
        if result.task.purpose == .ideaPill {
            saveIdeaPill(result)
            SmartUsageLedgerStore.record(result.usage)
            finishFinalTask(result.task)
            return
        }
        saveBacklogIfRequested(result)
        SmartUsageLedgerStore.record(result.usage)
        pendingPasteResults.append(result)
        drainPendingPasteResultsIfPossible()
    }

    private func saveIdeaPill(_ result: PendingPasteResult) {
        do {
            let content = result.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? result.sourceText ?? result.text
                : result.text
            let url = try BacklogWriter.saveIdeaPill(BacklogSaveContext(
                rawText: result.rawText,
                finalText: content,
                modeName: result.rewriteMode?.displayName ?? smartRewritePreference(for: result.task.purpose).displayName,
                targetAppName: currentTargetApp(for: result.task)?.localizedName,
                recordingSessionID: result.task.id
            ))
            LaunchDiagnostics.mark("idea_pill_saved task_id=\(result.task.id.uuidString) path=\(url.path)")
            if shouldUpdateInterface(for: result.task.id) {
                controller.setPrimaryStatus(
                    "闪念已保存",
                    detail: "已保存到闪念胶囊：\(url.lastPathComponent)",
                    tone: .success,
                    resetWaveform: true
                )
                hidePopup(after: 0, task: result.task)
            }
        } catch {
            LaunchDiagnostics.mark("idea_pill_save_failed task_id=\(result.task.id.uuidString) error=\(error.localizedDescription)")
            if shouldUpdateInterface(for: result.task.id) {
                controller.setPrimaryStatus(
                    "闪念保存失败",
                    detail: "已保留到最近转录：\(error.localizedDescription)",
                    tone: .warning,
                    resetWaveform: true
                )
                ToastPresenter.shared.show("闪念保存失败，已存历史", style: .warning)
                hidePopup(after: 0, task: result.task)
            }
        }
    }

    private func saveBacklogIfRequested(_ result: PendingPasteResult) {
        guard BacklogWriter.shouldSave(rawText: result.rawText) else { return }
        do {
            let content = result.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? result.sourceText ?? result.text
                : result.text
            let url = try BacklogWriter.save(BacklogSaveContext(
                rawText: result.rawText,
                finalText: content,
                modeName: controller.smartRewritePreference.displayName,
                targetAppName: currentTargetApp(for: result.task)?.localizedName,
                recordingSessionID: result.task.id
            ))
            LaunchDiagnostics.mark("backlog_saved task_id=\(result.task.id.uuidString) path=\(url.path)")
            if shouldUpdateInterface(for: result.task.id) {
                controller.detail.stringValue = "已存入 Backlog：\(url.lastPathComponent)"
            }
        } catch {
            LaunchDiagnostics.mark("backlog_save_failed task_id=\(result.task.id.uuidString) error=\(error.localizedDescription)")
            if shouldUpdateInterface(for: result.task.id) {
                controller.detail.stringValue = "Backlog 保存失败：\(error.localizedDescription)"
            }
        }
    }

    private func drainPendingPasteResultsIfPossible() {
        guard activeSession == nil, !recorder.isRecording else { return }
        guard !pendingPasteResults.isEmpty else {
            if case .recording = inputState {
                return
            }
            if case .finalizing = inputState {
                return
            }
            if case .pasting = inputState {
                return
            }
            inputState = .idle
            releaseASRResourcesIfMemoryElevated()
            return
        }
        if case .pasting = inputState {
            return
        }

        let result = pendingPasteResults.removeFirst()
        let pasteTarget = currentTargetApp(for: result.task)
        LaunchDiagnostics.mark(
            "paste_drain task_id=\(result.task.id.uuidString.prefix(8)) target=\(pasteTarget?.localizedName ?? "nil") frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil") fallback=\(result.task.targetApp?.localizedName ?? "nil")"
        )
        guard let pasteTarget else {
            skipAutomaticPaste(result)
            return
        }
        inputState = .pasting(result.task)
        workflowState.startPasting(taskID: result.task.id)
        let postPasteAction = autoSendPolicy.action(
            configuration: AutoSendSettingsStore.load(),
            purpose: result.task.purpose,
            text: result.text,
            targetBundleIdentifier: pasteTarget.bundleIdentifier,
            isTranslated: result.wasTranslationRequested
        )
        LaunchDiagnostics.mark(
            "auto_send_decision task_id=\(result.task.id.uuidString.prefix(8)) target_bundle=\(pasteTarget.bundleIdentifier ?? "nil") action=\(postPasteAction.rawValue) purpose=\(result.task.purpose.logName) translation_requested=\(result.wasTranslationRequested)"
        )
        pasteCoordinator.enqueue(
            taskID: result.task.id,
            text: result.text,
            targetApp: pasteTarget,
            postPasteAction: postPasteAction
        ) { [weak self] outcome in
            self?.handlePasteOutcome(outcome, result: result)
        }
    }

    private func skipAutomaticPaste(
        _ result: PendingPasteResult,
        detail: String = "当前目标不可自动粘贴，可在最近转录中复制"
    ) {
        let task = result.task
        let shouldUpdateInterface = shouldUpdateInterface(for: task.id)
        if shouldUpdateInterface {
            controller.setPrimaryStatus(
                "已保存到主页历史",
                detail: detail,
                tone: .warning,
                resetWaveform: true
            )
            hidePopup(after: 0, task: task)
        }
        inputState = .idle
        workflowState.finishTask(task.id)
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
    }

    private func finishFinalTask(_ task: RecordingTask) {
        if case .finalizing(let current) = inputState, current.id == task.id {
            inputState = .idle
        }
        workflowState.finishTask(task.id)
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
    }

    private func showEmptyRecording() {
        controller.setPrimaryStatus(
            "没有收到有效音频",
            detail: emptyRecordingDetail(),
            tone: .warning,
            resetWaveform: true
        )
        popup.hideAnimated()
    }

    private func emptyRecordingDetail() -> String {
        guard let reason = recorder.emptyRecordingReason else {
            return "未检测到人声。通话中请切换输入设备。"
        }
        if reason.contains("接近静音") {
            return "麦克风近似静音。请选通话正在用的麦克风。"
        }
        return "未收到麦克风输入。请选通话正在用的麦克风。"
    }

    private func handlePasteOutcome(_ outcome: PasteOutcome, result: PendingPasteResult) {
        let task = result.task
        if outcome.pasteCompletedAt != nil,
           let targetApp = currentTargetApp(for: task) {
            RecentTargetApplicationStore.record(targetApp)
        }
        let shouldUpdateInterface = shouldUpdateInterface(for: task.id)
        if shouldUpdateInterface {
            switch outcome {
            case .directInserted:
                controller.detail.stringValue = "识别结果已直接输入，未改动剪贴板"
                hidePopup(after: 0, task: task)
            case .restored:
                controller.detail.stringValue = "识别结果已粘贴，原剪贴板已恢复"
                hidePopup(after: 0, task: task)
            case .preservedUserClipboard:
                controller.detail.stringValue = "识别结果已粘贴，检测到新的剪贴板内容并已保留"
                hidePopup(after: 0, task: task)
            case .failed:
                controller.setPrimaryStatus(
                    "已保存到主页历史",
                    detail: "自动粘贴未完成，可在最近转录中复制",
                    tone: .warning,
                    resetWaveform: true
                )
                ToastPresenter.shared.show("未能自动粘贴，已存历史", style: .warning)
                hidePopup(after: 0, task: task)
            }
        }
        if activeSession == nil, !recorder.isRecording {
            inputState = .idle
        }
        workflowState.finishTask(task.id)
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
    }

    private func releaseASRResourcesIfMemoryElevated() {
        // 已取消“空闲定时卸载”：模型平时保持热加载，避免久未说话后开口第一句因重载卡顿。
        // 内存治理只保留“高内存时释放”这条安全网。
        idleASRUnloadWorkItem?.cancel()
        idleASRUnloadWorkItem = nil
        guard !isSystemSleeping else { return }
        guard !isInWakeRecoveryGrace else {
            if !didLogWakeRecoveryReloadSkip {
                LaunchDiagnostics.mark("release_asr_resources skipped=wake_recovery")
                didLogWakeRecoveryReloadSkip = true
            }
            return
        }
        guard isIdleForASRResourceRelease else { return }
        evaluateManagedLLMMemoryLifecycle(reason: "memory_check")
        let currentMemoryMB = MemoryMonitor.currentFootprintMB
        let thresholdMB = MemoryMonitor.warnThresholdMB
        guard currentMemoryMB >= thresholdMB else {
            if didFlushASRArenaForElevatedMemory {
                LaunchDiagnostics.mark("asr_memory_guard_reset memory_mb=\(currentMemoryMB) threshold_mb=\(thresholdMB)")
            }
            didFlushASRArenaForElevatedMemory = false
            return
        }
        guard !didFlushASRArenaForElevatedMemory else { return }
        // 冷却期内不重复释放，避免 flush→reload→flush 抖动。
        if let lastFlush = lastASRArenaFlushAt,
           Date().timeIntervalSince(lastFlush) < asrArenaFlushCooldownSeconds {
            return
        }
        didFlushASRArenaForElevatedMemory = true
        releaseASRResourcesIfIdle(reason: "memory_warn", memoryMB: currentMemoryMB)
    }

    private func releaseASRResourcesIfIdle(reason: String, memoryMB: Int? = nil) {
        guard isIdleForASRResourceRelease else { return }
        idleASRUnloadWorkItem?.cancel()
        idleASRUnloadWorkItem = nil
        lastASRArenaFlushAt = Date()
        let currentMemoryMB = memoryMB ?? MemoryMonitor.currentFootprintMB
        LaunchDiagnostics.mark(
            "release_asr_resources reason=\(reason) memory_mb=\(currentMemoryMB) threshold_mb=\(MemoryMonitor.warnThresholdMB) total_memory_mb=\(MemoryMonitor.totalPhysicalMemoryMB)"
        )
        // 释放被高水位撑大的 onnxruntime 内存池，并立刻用全新内存池热加载回来：
        // 清掉膨胀，但不让下一句录音承担重载延迟（reload = flush + warmUp）。
        nativeASR.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.controller.updateMemoryReadout()
        }
    }

    private func evaluateManagedLLMMemoryLifecycle(
        reason: String,
        coldPrewarmAllowed: Bool = false,
        now: Date = Date()
    ) {
        let service = ManagedLLMRuntimeService.shared
        let mainFootprintMB = MemoryMonitor.currentFootprintMB
        let workerSnapshot = service.workerMemorySnapshot
        let workerFootprintMB = workerSnapshot.footprintMB
        let totalFootprintMB = mainFootprintMB + workerFootprintMB
        let action = ManagedLLMLifecyclePolicy.evaluate(
            .init(
                qwenSelected: SmartAIModelStore.load().provider == .typeWhaleMLX,
                workerRunning: workerSnapshot.isRunning,
                totalFootprintMB: totalFootprintMB,
                projectedWorkerFootprintMB: managedLLMProjectedFootprintMB,
                warnThresholdMB: MemoryMonitor.warnThresholdMB,
                coldPrewarmAllowed: coldPrewarmAllowed,
                recoveryNotBefore: managedLLMMemoryRecoveryNotBefore
            ),
            now: now
        )
        switch action {
        case .none:
            return
        case .stopForMemory:
            managedLLMProjectedFootprintMB = max(
                managedLLMProjectedFootprintMB,
                workerFootprintMB
            )
            managedLLMMemoryRecoveryNotBefore = now.addingTimeInterval(
                ManagedLLMLifecyclePolicy.recoveryCooldown
            )
            LaunchDiagnostics.mark(
                "managed_mlx memory_stop reason=\(reason) main_mb=\(mainFootprintMB) worker_mb=\(workerFootprintMB) total_mb=\(totalFootprintMB) threshold_mb=\(MemoryMonitor.warnThresholdMB)"
            )
            stopManagedLLM(reason: "memory_warn")
        case .prewarm:
            managedLLMMemoryRecoveryNotBefore = nil
            managedLLMProjectedFootprintMB = 0
            LaunchDiagnostics.mark(
                "managed_mlx memory_recover reason=\(reason) main_mb=\(mainFootprintMB) worker_mb=\(workerFootprintMB) total_mb=\(totalFootprintMB)"
            )
            prewarmManagedLLMIfNeeded(reason: reason)
        }
    }

    private var isIdleForASRResourceRelease: Bool {
        if activeSession != nil ||
            recorder.isRecording ||
            isFinalRewriteInFlight ||
            isTranslationInFlight ||
            !pendingPasteResults.isEmpty ||
            realtimeBusy {
            return false
        }
        switch inputState {
        case .idle, .failed:
            return true
        case .recording, .finalizing, .pasting:
            return false
        }
    }

    private func cancelIdleASRUnload() {
        idleASRUnloadWorkItem?.cancel()
        idleASRUnloadWorkItem = nil
    }

    private func addRecentTranscription(for result: PendingPasteResult, completedAt: Date) {
        let totalSeconds = max(
            0,
            completedAt.timeIntervalSince(result.task.finishRequestedAt)
        )
        controller.addRecentTranscription(
            result.text,
            recognitionSeconds: totalSeconds,
            sourceText: result.sourceText,
            translatedText: result.translatedText,
            translationDirection: result.translationDirection,
            usage: result.usage
        )
    }

    private func hidePopup(after delay: TimeInterval, task: RecordingTask) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.shouldHidePopup(for: task.id) == true else { return }
            self?.popup.hideAnimated()
        }
    }

    private func shouldUpdateInterface(for taskID: UUID) -> Bool {
        workflowState.shouldUpdateInterface(for: taskID, isRecording: recorder.isRecording)
    }

    private func shouldHidePopup(for taskID: UUID) -> Bool {
        workflowState.canHidePopup(for: taskID, isRecording: recorder.isRecording)
    }

    private func markFinalTaskForSubmission(_ taskID: UUID) -> Bool {
        guard workflowState.markFinalTaskForSubmission(taskID) else {
            LaunchDiagnostics.mark("final task ignored duplicate task_id=\(taskID.uuidString)")
            return false
        }
        return true
    }

    /// 每个音频缓冲触发一次：推进与录音总时长相关的安全守卫。
    /// 停顿自动完成只由带 task ID 的 Silero 结果触发，避免在最新探测仍在途时使用旧状态抢先结束。
    private func tickRecordingGuards() {
        guard recorder.isRecording else { return }
        scheduleLongFormDiskSafetyCheck()
        if enforceMaxRecordingDuration() { return }
        if enforceNoTextTimeout() { return }
    }

    private func scheduleLongFormDiskSafetyCheck() {
        guard let session = activeSession,
              session.experimentalPreviewSettings.longFormIncrementalOutputEnabled,
              longFormDiskSafetyProbeGate.beginIfDue(at: Date()) else { return }
        let taskID = session.id
        let recordingsURL = AppPaths.recordings
        longFormDiskSafetyProbeTaskID = taskID
        longFormDiskSafetyQueue.async { [weak self] in
            let values = try? recordingsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = values?.volumeAvailableCapacityForImportantUsage
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.longFormDiskSafetyProbeTaskID == taskID else { return }
                self.longFormDiskSafetyProbeTaskID = nil
                self.longFormDiskSafetyProbeGate.complete()
                guard self.recorder.isRecording,
                      self.activeSession?.id == taskID,
                      self.activeSession?.experimentalPreviewSettings.longFormIncrementalOutputEnabled == true,
                      let available,
                      available < 512 * 1024 * 1024 else { return }
                LaunchDiagnostics.mark("long_form_low_disk available_bytes=\(available)")
                self.controller.setPrimaryStatus(
                    "磁盘空间不足",
                    detail: "已安全停止长录音并保留现有内容",
                    tone: .warning,
                    resetWaveform: false
                )
                self.suppressNextHotkeyUp = self.hotkeyIsPressed
                self.hotkeyIsPressed = false
                self.hotkeyPressGesturePolicy.reset()
                self.finishRecording(reason: "long_form_low_disk")
            }
        }
    }

    /// 人声门控核心：录音过程中约每 0.4s 收到一段最近窗口 PCM，交给 Silero 判定当前是否有人声。
    /// 本方法在 main 上被调用（recorder 已派发）；原生 VAD 在其专用串行队列上跑，完成后回到 main 更新状态。
    private func receiveVoiceProbe(taskID: UUID, samples: [Float], sampleRate: Int) {
        guard activeSession?.id == taskID,
              voiceDetectionAvailable,
              recorder.isRecording else { return }
        voiceProbeSequence += 1
        let request = VoiceProbeRequest(
            taskID: taskID,
            samples: samples,
            sampleRate: sampleRate,
            capturedAt: Date(),
            sequence: voiceProbeSequence
        )
        if voiceProbeInFlight {
            guard pendingVoiceProbes.enqueue(request) else {
                voiceDetectionAvailable = false
                pendingVoiceProbes.removeAll()
                recorder.updateRealtimeVoiceActive(true)
                LaunchDiagnostics.mark(
                    "vad_probe_backpressure_disable task_id=\(taskID.uuidString.prefix(8)) capacity=\(pendingVoiceProbes.capacity)"
                )
                return
            }
            return
        }
        startVoiceProbe(request)
    }

    private func startVoiceProbe(_ request: VoiceProbeRequest) {
        guard activeSession?.id == request.taskID,
              voiceDetectionAvailable,
              recorder.isRecording,
              !voiceProbeInFlight else { return }
        voiceProbeInFlight = true
        let probeStartedAt = Date()
        vadBridge.containsSpeech(samples: request.samples, sampleRate: request.sampleRate) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.activeSession?.id == request.taskID, self.recorder.isRecording else {
                    LaunchDiagnostics.mark(
                        "vad_probe_ignored reason=stale_task task_id=\(request.taskID.uuidString.prefix(8)) current_task=\(self.activeSession?.id.uuidString.prefix(8) ?? "-")"
                    )
                    return
                }
                guard self.voiceDetectionAvailable else {
                    self.voiceProbeInFlight = false
                    LaunchDiagnostics.mark(
                        "vad_probe_ignored reason=backpressure_disabled task_id=\(request.taskID.uuidString.prefix(8))"
                    )
                    return
                }
                self.voiceProbeInFlight = false
                let decidedAt = Date()
                let probeMs = Int(decidedAt.timeIntervalSince(probeStartedAt) * 1000)
                let decisionDelayMs = Int(decidedAt.timeIntervalSince(request.capturedAt) * 1000)
                let previewText = (self.activeSession?.committedPreviewText ?? "")
                    + (self.activeSession?.latestPreviewText ?? "")
                let hasMeaningfulPreview = isMeaningfulRecognitionText(previewText)
                switch result {
                case .success(true):
                    self.latestVoiceProbeHasSpeech = true
                    self.latestVoiceProbeCapturedAt = request.capturedAt
                    self.voiceEverDetected = true
                    self.lastVoiceAt = request.capturedAt
                    // 有人声 → 通知录音器：当前不宜在此切块（避免切词）。
                    self.recorder.updateRealtimeVoiceActive(true)
                    _ = self.autoFinishPolicy.evaluateProbe(
                        hasSpeech: true,
                        capturedAt: request.capturedAt,
                        autoFinishEnabled: self.longFormTranscriptionSession?.usesPauseAutoFinish
                            ?? self.controller.autoFinishAfterPauseEnabled,
                        isHoldActivation: self.activeSession?.activation == .hold,
                        hasMeaningfulPreview: hasMeaningfulPreview
                    )
                case .success(false):
                    self.latestVoiceProbeHasSpeech = false
                    self.latestVoiceProbeCapturedAt = request.capturedAt
                    // 停顿 → 录音器可在此处对齐分块边界并冻结提交。
                    self.recorder.updateRealtimeVoiceActive(false)
                    let decision = self.autoFinishPolicy.evaluateProbe(
                        hasSpeech: false,
                        capturedAt: request.capturedAt,
                        autoFinishEnabled: self.longFormTranscriptionSession?.usesPauseAutoFinish
                            ?? self.controller.autoFinishAfterPauseEnabled,
                        isHoldActivation: self.activeSession?.activation == .hold,
                        hasMeaningfulPreview: hasMeaningfulPreview,
                        canCommitDecision: self.pendingVoiceProbes.isEmpty
                    )
                    self.handleAutoFinishDecision(
                        decision,
                        taskID: request.taskID,
                        capturedAt: request.capturedAt,
                        previewCharacters: previewText.count,
                        probeMilliseconds: probeMs,
                        decisionDelayMilliseconds: decisionDelayMs
                    )
                case .failure(let error):
                    self.latestVoiceProbeHasSpeech = nil
                    self.latestVoiceProbeCapturedAt = nil
                    // Silero 实时检测出错 → 停用人声检测：关闭停顿自动结束，仅保留手动停止与硬上限。
                    // 同时让分块回到「硬上限驱动」（视为一直有人声，不在停顿处切）。
                    self.voiceDetectionAvailable = false
                    self.pendingVoiceProbes.removeAll()
                    self.recorder.updateRealtimeVoiceActive(true)
                    LaunchDiagnostics.mark(
                        "vad_probe_unavailable task_id=\(request.taskID.uuidString.prefix(8)) probe_ms=\(probeMs) decision_delay_ms=\(decisionDelayMs) error=\"\(error.localizedDescription)\""
                    )
                }
                if self.activeSession?.id == request.taskID,
                   self.voiceDetectionAvailable,
                   let pending = self.pendingVoiceProbes.dequeue() {
                    self.startVoiceProbe(pending)
                }
            }
        }
    }

    private func handleAutoFinishDecision(
        _ decision: RecordingAutoFinishDecision,
        taskID: UUID,
        capturedAt: Date,
        previewCharacters: Int,
        probeMilliseconds: Int,
        decisionDelayMilliseconds: Int
    ) {
        guard activeSession?.id == taskID else { return }
        let recordingElapsed = recordingStartedAt.map { capturedAt.timeIntervalSince($0) } ?? 0
        switch decision {
        case .continueRecording:
            return
        case .awaitingNoSpeechConfirmation:
            LaunchDiagnostics.mark(
                "vad_probe_no_speech_pending_confirmation task_id=\(taskID.uuidString.prefix(8)) recording_ms=\(Int(recordingElapsed * 1000)) preview_chars=\(previewCharacters) probe_ms=\(probeMilliseconds) decision_delay_ms=\(decisionDelayMilliseconds)"
            )
            return
        case .deferredForNewerAudio:
            LaunchDiagnostics.mark(
                "vad_probe_finish_deferred reason=newer_audio_pending task_id=\(taskID.uuidString.prefix(8)) recording_ms=\(Int(recordingElapsed * 1000)) probe_ms=\(probeMilliseconds) decision_delay_ms=\(decisionDelayMilliseconds)"
            )
            return
        case .finishAfterPause(let silenceDuration):
            LaunchDiagnostics.mark(
                "recording_auto_finish reason=pause task_id=\(taskID.uuidString.prefix(8)) silence_ms=\(Int(silenceDuration * 1000)) recording_ms=\(Int(recordingElapsed * 1000)) preview_chars=\(previewCharacters) probe_ms=\(probeMilliseconds) decision_delay_ms=\(decisionDelayMilliseconds)"
            )
            suppressNextHotkeyUp = hotkeyIsPressed
            hotkeyIsPressed = false
            hotkeyPressGesturePolicy.reset()
            finishRecording(reason: "pause")
        case .cancelInitialSilence(let elapsed):
            LaunchDiagnostics.mark(
                "recording_auto_finish reason=initial_silence task_id=\(taskID.uuidString.prefix(8)) elapsed_ms=\(Int(elapsed * 1000)) preview_chars=\(previewCharacters) probe_ms=\(probeMilliseconds) decision_delay_ms=\(decisionDelayMilliseconds)"
            )
            cancelInitialSilenceRecording(taskID: taskID, elapsed: elapsed)
        }
    }

    private func cancelInitialSilenceRecording(taskID: UUID, elapsed: TimeInterval) {
        guard activeSession?.id == taskID else { return }
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        hotkeyPressGesturePolicy.reset()
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        LaunchDiagnostics.mark(
            "recording_cancel_requested reason=initial_silence task_id=\(taskID.uuidString.prefix(8)) elapsed_ms=\(Int(elapsed * 1000))"
        )
        recorder.cancel()
        clearActiveRecording()
        cancelRecordingStopHandoff(reason: "initial_silence")
        trackedTargetTaskID = nil
        trackedTargetApp = nil
        cancelActiveWorkflow(reason: "initial_silence")
        inputState = .idle
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
        controller.setPrimaryStatus(
            "无输入已停止",
            detail: String(format: "约 %.0f 秒未检测到语音，已取消本次空录音。", elapsed),
            tone: .warning,
            resetWaveform: true
        )
        popup.show(state: "无输入已停止", draft: "未检测到语音")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else { return }
            guard self.activeSession == nil,
                  !self.recorder.isRecording,
                  case .idle = self.inputState else { return }
            self.popup.hideAnimated()
        }
    }

    /// 录音超过单次硬上限时自动结束并识别，封住 ASR 内存峰值。返回是否已触发结束。
    private func enforceRecordingTimeoutsIfNeeded() {
        guard recorder.isRecording || activeSession != nil else { return }
        if recorder.isRecording, activeSession == nil {
            LaunchDiagnostics.mark("recording_cancel_requested reason=missing_session task_id=-")
            LaunchDiagnostics.mark("recording_safety_cancel reason=missing_session")
            recorder.cancel()
            clearActiveRecording()
            cancelRecordingStopHandoff(reason: "missing_recording_session")
            trackedTargetTaskID = nil
            trackedTargetApp = nil
            cancelActiveWorkflow(reason: "missing_recording_session")
            inputState = .idle
            drainPendingPasteResultsIfPossible()
            return
        }
        if enforceMaxRecordingDuration() { return }
        if enforceNoTextTimeout() { return }
    }

    /// 录音超过单次硬上限时自动结束并识别，封住异常长录音的能耗和内存峰值。返回是否已触发结束。
    private func enforceMaxRecordingDuration() -> Bool {
        guard let startedAt = recordingStartedAt else { return false }
        let maximum = Timing.maxRecordingSeconds
        guard Date().timeIntervalSince(startedAt) >= maximum else { return false }
        let durationText = Self.formatMaxRecordingDuration(maximum)
        LaunchDiagnostics.mark("recording_auto_finish reason=max_duration seconds=\(Int(maximum))")
        controller.setPrimaryStatus(
            "已达单次最长录音",
            detail: "单次最长约 \(durationText)，已自动结束并开始识别",
            tone: .warning,
            resetWaveform: false
        )
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        hotkeyPressGesturePolicy.reset()
        finishRecording(reason: "max_duration")
        return true
    }

    private static func formatMaxRecordingDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded())) 秒"
        }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes) 分钟"
    }

    /// 录音中持续无语音/文字产出超过上限（默认 5 分钟）→ 自动收尾。
    /// 如果本轮已经说过话，正常结束并识别，保留历史；如果从未有人声，取消空录音以避免无意义识别。
    private func enforceNoTextTimeout() -> Bool {
        if longFormTranscriptionSession?.usesNoTextTimeout == false { return false }
        guard let startedAt = recordingStartedAt else { return false }
        // 说过话就从最后一次人声算起；从未出声则从开始录音算起。
        let reference = voiceEverDetected ? (lastVoiceAt ?? startedAt) : startedAt
        guard Date().timeIntervalSince(reference) >= Timing.noTextTimeoutSeconds else { return false }
        let minutes = Int(Timing.noTextTimeoutSeconds / 60)
        LaunchDiagnostics.mark(
            "recording_auto_finish reason=no_text_timeout seconds=\(Int(Timing.noTextTimeoutSeconds)) had_voice=\(voiceEverDetected)"
        )
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        hotkeyPressGesturePolicy.reset()
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        if voiceEverDetected {
            controller.setPrimaryStatus(
                "已自动结束录音",
                detail: "连续约 \(minutes) 分钟无语音输入，正在识别并保留本次内容。",
                tone: .warning,
                resetWaveform: false
            )
            popup.show(state: "自动结束", draft: "正在识别")
            finishRecording(reason: "no_text_timeout")
            return true
        }
        recorder.cancel()
        clearActiveRecording()
        cancelRecordingStopHandoff(reason: "no_text_timeout")
        trackedTargetTaskID = nil
        trackedTargetApp = nil
        cancelActiveWorkflow(reason: "no_text_timeout")
        inputState = .idle
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
        controller.setPrimaryStatus(
            "无输入已自动停止",
            detail: "连续约 \(minutes) 分钟无语音输入，已自动结束录音，未做识别。",
            tone: .warning,
            resetWaveform: true
        )
        popup.show(state: "无输入已停止", draft: "约 \(minutes) 分钟无输入")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.popup.hideAnimated()
        }
        return true
    }

    private func cancelAutoFinishTimer() {
        autoFinishWorkItem?.cancel()
        autoFinishWorkItem = nil
    }

    private func cancelInitialSilenceTimer() {
        initialSilenceWorkItem?.cancel()
        initialSilenceWorkItem = nil
    }
}
