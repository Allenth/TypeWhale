import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SpeechInputCoordinator {
    private enum Timing {
        static let autoFinishPauseSeconds: TimeInterval = 1.5
        static let initialSilenceAutoFinishSeconds: TimeInterval = 3.0
        static let holdToRecordSeconds: TimeInterval = 0.28
    }

    /// 基于音频能量的语音活动检测（VAD）阈值，与 ASR 解耦，保证静音/人离判定每次稳定一致。
    private enum VAD {
        /// 7 段能量（已归一到 0.12~1）的峰值高于此值即判为"有人声"。环境噪声约 0.12~0.2，留足余量。
        static let speechBandThreshold: Float = 0.30
    }

    private var recordingStartedAt: Date?
    private var lastVoiceAt: Date?
    private var voiceEverDetected = false

    private let controller: MainViewController
    private let hideMainWindow: () -> Void
    private let shouldKeepMainWindowVisibleForScreenshot: () -> Bool
    private let recorder = AudioRecorder()
    private let popup = RecordingPanel()
    private let hotkey = HotkeyMonitor()
    private let modelInstaller = SenseVoiceModelInstaller()
    private let nativeASR = NativeSenseVoiceBridge(runtimeName: "shared")
    private let outputAudioDucker = OutputAudioDucker()
    private let smartEngine = DeepSeekRewriteEngine()
    private lazy var asr = SenseVoiceRouter(runtimeName: "final", native: nativeASR)
    private lazy var realtimeASR = SenseVoiceRouter(runtimeName: "realtime", native: nativeASR)
    private lazy var smartInputRouter = SmartInputRouter(engine: smartEngine)
    private lazy var screenshotCoordinator = ScreenshotCoordinator { [weak self] status, detail, tone in
        self?.controller.setPrimaryStatus(status, detail: detail, tone: tone, resetWaveform: true)
    }
    private let pasteCoordinator = PasteCoordinator()
    private var inputState: SpeechInputState = .idle
    private var activeSession: SpeechSession?
    private var pendingPasteResults: [PendingPasteResult] = []
    private var latestSubmittedTaskID: UUID?
    private var completedFinalTaskIDs: Set<UUID> = []
    private var realtimeBusy = false
    private var pendingRealtimeSnapshot: RealtimeSnapshotRequest?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var trackedTargetTaskID: UUID?
    private var trackedTargetApp: NSRunningApplication?
    private var hotkeyIsPressed = false
    private var longPressWorkItem: DispatchWorkItem?
    private var autoFinishWorkItem: DispatchWorkItem?
    private var initialSilenceWorkItem: DispatchWorkItem?
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
    private var autoTranslateHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.autoTranslateStorageKey
    )
    private var mainWindowHotkeyBinding = HotkeyBinding.loadOptional(
        storageKey: HotkeyBinding.mainWindowStorageKey
    )

    init(
        controller: MainViewController,
        hideMainWindow: @escaping () -> Void,
        shouldKeepMainWindowVisibleForScreenshot: @escaping () -> Bool
    ) {
        self.controller = controller
        self.hideMainWindow = hideMainWindow
        self.shouldKeepMainWindowVisibleForScreenshot = shouldKeepMainWindowVisibleForScreenshot
    }

    func start() {
        recorder.onBands = { [weak self] bands in
            self?.popup.updateBands(bands)
            self?.controller.updateInputBands(bands)
            self?.observeAudioEnergy(bands)
        }
        recorder.onRealtimeSnapshot = { [weak self] taskID, url in
            self?.receiveRealtimeSnapshot(taskID: taskID, url: url)
        }
        controller.updateHotkeys(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding
        )
        hotkey.update(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding
        )
        hotkey.onDown = { [weak self] channel, binding in self?.handleHotkeyDown(channel: channel, binding: binding) }
        hotkey.onUp = { [weak self] channel, binding in self?.handleHotkeyUp(channel: channel, binding: binding) }
        hotkey.onAutoTranslateToggle = { [weak self] in self?.toggleAutoTranslateFromHotkey() }
        hotkey.onScreenshot = { [weak self] in self?.beginScreenshotFromHotkey() }
        hotkey.onMainWindow = { [weak self] in self?.showMainWindowFromHotkey() }
        popup.onCycleMode = { [weak self] in self?.cycleSmartRewriteModeFromCapsule() }
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
            }
        }
        controller.onInstallModel = { [weak self] in
            self?.modelInstaller.install()
        }
        controller.onHotkeysChange = { [weak self] primary, secondary, screenshot, autoTranslate, mainWindow in
            self?.primaryHotkeyBinding = primary
            self?.secondaryHotkeyBinding = secondary
            self?.screenshotHotkeyBinding = screenshot
            self?.autoTranslateHotkeyBinding = autoTranslate
            self?.mainWindowHotkeyBinding = mainWindow
            self?.hotkey.update(
                primary: primary,
                secondary: secondary,
                screenshot: screenshot,
                autoTranslate: autoTranslate,
                mainWindow: mainWindow
            )
            self?.refreshPermissions()
        }
        modelInstaller.refresh()
        hotkey.start()
        asr.start()
        realtimeASR.start()
        startObservingTargetApplicationChanges()
        refreshPermissions()
        PermissionDiagnosticsProvider.requestAccessibilityIfNeeded()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
                self?.hotkey.start()
            }
        }
        PermissionDiagnosticsProvider.requestMicrophone { [weak self] in self?.refreshPermissions() }
    }

    func stop() {
        longPressWorkItem?.cancel()
        cancelAutoFinishTimer()
        cancelInitialSilenceTimer()
        recorder.cancel()
        clearActiveRecording()
        pendingPasteResults.removeAll()
        inputState = .idle
        stopObservingTargetApplicationChanges()
        asr.stop()
        realtimeASR.stop()
    }

    private func refreshPermissions() {
        let permissions = PermissionDiagnosticsProvider.current()
        let globalListening = hotkey.isGlobalListening
        UserDefaults.standard.synchronize()
        controller.micStatus.stringValue = permissions.microphoneAuthorized ? "● 已开启" : "● 未开启"
        controller.micStatus.textColor = permissions.microphoneAuthorized ? .systemGreen : .systemRed
        controller.accessibilityStatus.stringValue = permissions.accessibilityTrusted ? "● 已开启" : "● 未开启"
        controller.accessibilityStatus.textColor = permissions.accessibilityTrusted ? .systemGreen : .systemRed
        controller.screenRecordingStatus.stringValue = permissions.screenRecordingAuthorized ? "● 已开启" : "● 未开启"
        controller.screenRecordingStatus.textColor = permissions.screenRecordingAuthorized ? .systemGreen : .systemRed
        if globalListening {
            controller.hotkeyStatus.stringValue = "● 监听中"
            controller.hotkeyStatus.textColor = .systemGreen
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
        guard trackedTargetTaskID != nil else { return }
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        updateTrackedTargetApp(app)
    }

    @discardableResult
    private func refreshTrackedTargetFromFrontmost() -> NSRunningApplication? {
        updateTrackedTargetApp(NSWorkspace.shared.frontmostApplication)
        return trackedTargetApp
    }

    private func updateTrackedTargetApp(_ app: NSRunningApplication?) {
        guard trackedTargetTaskID != nil else { return }
        let target = pasteableTargetApp(app)
        trackedTargetApp = target
        if var session = activeSession, session.id == trackedTargetTaskID {
            session.targetApp = target
            activeSession = session
        }
        popup.updateTargetApp(
            appIcon: app?.icon,
            appName: displayNameForSelectedTarget(app)
        )
    }

    private func currentTargetApp(for task: RecordingTask) -> NSRunningApplication? {
        currentTargetApp(taskID: task.id, fallback: task.targetApp)
    }

    private func currentTargetApp(taskID: UUID, fallback: NSRunningApplication?) -> NSRunningApplication? {
        guard trackedTargetTaskID == taskID else { return fallback }
        if let trackedTargetApp, !trackedTargetApp.isTerminated {
            return trackedTargetApp
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
        guard app.localizedName?.isEmpty == false else {
            return nil
        }
        return app
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

    private func handleHotkeyDown(channel: SpeechInputChannel, binding: HotkeyBinding) {
        if screenshotCoordinator.isActive { return }
        hotkeyIsPressed = true
        longPressWorkItem?.cancel()
        guard activeSession == nil, !recorder.isRecording else { return }

        let displayName = binding.displayName
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hotkeyIsPressed, !self.recorder.isRecording else { return }
            self.startRecording(
                instructions: "松开 \(displayName) 完成录音",
                activation: .hold,
                channel: channel
            )
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.holdToRecordSeconds, execute: workItem)
    }

    private func handleHotkeyUp(channel: SpeechInputChannel, binding: HotkeyBinding) {
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
            finishRecording()
        case nil:
            guard !recorder.isRecording else {
                finishRecording()
                return
            }
            startRecording(
                instructions: "再次按下 \(displayName) 完成录音",
                activation: .toggle,
                channel: channel
            )
        }
    }

    private func toggleAutoTranslateFromHotkey() {
        controller.toggleAutoTranslateFromShortcut()
        popup.updateAutoTranslateEnabled(controller.autoTranslateEnabled)
    }

    private func showMainWindowFromHotkey() {
        if controller.view.window?.isMiniaturized == true {
            controller.view.window?.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.view.window?.makeKeyAndOrderFront(nil)
    }

    private func cycleSmartRewriteModeFromCapsule() {
        let next = controller.cycleSmartRewritePreference()
        popup.updateModeName(next.displayName)
    }

    private func beginScreenshotFromHotkey() {
        guard activeSession == nil, !recorder.isRecording else { return }
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        hotkeyIsPressed = false
        if !shouldKeepMainWindowVisibleForScreenshot() {
            hideMainWindow()
        }
        screenshotCoordinator.begin()
    }

    private func startRecording(
        instructions: String,
        activation: RecordingActivation,
        channel: SpeechInputChannel? = nil
    ) {
        guard !recorder.isRecording else { return }
        let selectedBackend = controller.asrBackend
        let resolvedBackend = selectedBackend.resolvedBackend
        let realtimeEnabled = controller.realtimePreviewEnabled && resolvedBackend == .senseVoice
        let taskID = UUID()
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let initialTargetApp = pasteableTargetApp(frontmostApp)
        let session = SpeechSession(
            id: taskID,
            targetApp: initialTargetApp,
            configuration: ASRConfiguration(languageMode: .chinese, backend: selectedBackend),
            activation: activation,
            realtimeEnabled: realtimeEnabled,
            latestPreviewText: ""
        )
        activeSession = session
        trackedTargetTaskID = taskID
        trackedTargetApp = initialTargetApp
        inputState = .recording(taskID)
        controller.updateRealtimeDraft(realtimeEnabled
            ? "正在等待第一段实时文本…"
            : (resolvedBackend == .qwen3ASR ? "Qwen3-ASR 模式下实时预览暂不启用" : "胶囊实时预览已关闭"))
        controller.setPrimaryStatus("录音中", detail: instructions, tone: .listening)
        popup.show(state: "录音中", draft: "")
        popup.setContext(
            appIcon: frontmostApp?.icon,
            appName: displayNameForSelectedTarget(frontmostApp),
            modeName: controller.smartRewritePreference.displayName,
            autoTranslateEnabled: controller.autoTranslateEnabled
        )
        outputAudioDucker.duckIfNeeded(enabled: controller.duckSystemAudioWhileRecordingEnabled)
        do {
            try recorder.start(
                taskID: taskID,
                realtimeEnabled: realtimeEnabled,
                inputDeviceID: AudioInputDeviceProvider.selectedDeviceID()
            )
            recordingStartedAt = Date()
            lastVoiceAt = nil
            voiceEverDetected = false
        } catch {
            cancelAutoFinishTimer()
            clearActiveRecording()
            controller.setPrimaryStatus("无法开始录音", detail: error.localizedDescription, tone: .error, resetWaveform: true)
            popup.show(state: "录音失败")
        }
    }

    private func finishRecording() {
        cancelAutoFinishTimer()
        guard let session = activeSession else { return }
        let taskID = session.id
        let configuration = session.configuration
        refreshTrackedTargetFromFrontmost()
        let targetApp = currentTargetApp(taskID: taskID, fallback: session.targetApp)
        let result: (URL, TimeInterval)?
        do {
            result = try recorder.stop()
        } catch {
            clearActiveRecording()
            controller.setPrimaryStatus("保存录音失败", detail: error.localizedDescription, tone: .error, resetWaveform: true)
            popup.show(state: "保存失败", draft: "")
            return
        }
        clearActiveRecording()
        guard let (url, duration) = result else {
            inputState = .idle
            drainPendingPasteResultsIfPossible()
            showEmptyRecording()
            return
        }
        discardPendingRealtimeSnapshot()
        let task = RecordingTask(
            id: taskID,
            audioURL: url,
            targetApp: targetApp,
            configuration: configuration,
            duration: duration,
            finishRequestedAt: Date()
        )
        inputState = .finalizing(task)
        latestSubmittedTaskID = taskID
        drainPendingPasteResultsIfPossible()
        controller.setPrimaryStatus(
            "正在检测人声",
            detail: String(format: "已完整录制 %.1f 秒", duration),
            tone: .processing,
            resetWaveform: true
        )
        popup.show(state: "检测中")
        asr.containsSpeech(audio: url) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                let shouldUpdateInterface = self.shouldUpdateInterface(for: taskID)
                switch response {
                case .failure(let error):
                    if shouldUpdateInterface {
                        self.controller.setPrimaryStatus(
                            "人声检测失败",
                            detail: error.localizedDescription,
                            tone: .error,
                            resetWaveform: true
                        )
                        self.popup.show(state: "检测失败", draft: "")
                    }
                    self.finishFinalTask(task)
                case .success(false):
                    if shouldUpdateInterface {
                        self.showEmptyRecording()
                    }
                    self.finishFinalTask(task)
                case .success(true):
                    if shouldUpdateInterface {
                        self.controller.setPrimaryStatus(
                            "正在识别",
                            detail: String(format: "已完整录制 %.1f 秒", duration),
                            tone: .processing,
                            resetWaveform: true
                        )
                        self.popup.show(state: "识别中", draft: "")
                    }
                    self.asr.transcribe(
                        audio: task.audioURL,
                        configuration: task.configuration
                    ) { [weak self] response in
                        DispatchQueue.main.async { self?.handle(response, task: task) }
                    }
                }
            }
        }
    }

    private func clearActiveRecording() {
        cancelAutoFinishTimer()
        cancelInitialSilenceTimer()
        outputAudioDucker.restore()
        activeSession = nil
        controller.resetInputBands()
        discardPendingRealtimeSnapshot()
    }

    private func discardPendingRealtimeSnapshot() {
        if let pendingRealtimeSnapshot {
            try? FileManager.default.removeItem(at: pendingRealtimeSnapshot.audioURL)
        }
        pendingRealtimeSnapshot = nil
    }

    private func receiveRealtimeSnapshot(taskID: UUID, url: URL) {
        guard let session = activeSession, taskID == session.id else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if realtimeBusy {
            if let pendingRealtimeSnapshot {
                try? FileManager.default.removeItem(at: pendingRealtimeSnapshot.audioURL)
            }
            pendingRealtimeSnapshot = RealtimeSnapshotRequest(
                taskID: taskID,
                audioURL: url,
                configuration: session.configuration
            )
            return
        }
        transcribeRealtime(taskID: taskID, url: url, configuration: session.configuration)
    }

    private func transcribeRealtime(taskID: UUID, url: URL, configuration: ASRConfiguration) {
        realtimeBusy = true
        realtimeASR.containsSpeech(audio: url) { [weak self] vadResponse in
            DispatchQueue.main.async {
                guard let self else { return }
                guard taskID == self.activeSession?.id else {
                    try? FileManager.default.removeItem(at: url)
                    self.finishRealtimeSnapshot()
                    return
                }
                switch vadResponse {
                case .failure:
                    try? FileManager.default.removeItem(at: url)
                    self.finishRealtimeSnapshot()
                case .success(false):
                    try? FileManager.default.removeItem(at: url)
                    self.finishRealtimeSnapshot()
                case .success(true):
                    self.realtimeASR.transcribe(
                        audio: url,
                        configuration: configuration
                    ) { [weak self] response in
                        DispatchQueue.main.async {
                            try? FileManager.default.removeItem(at: url)
                            guard let self else { return }
                            if taskID == self.activeSession?.id,
                               case .success(let value) = response,
                                (value["error"] as? String ?? "").isEmpty {
                                let text = cleanRecognitionText(value["text"] as? String ?? "", languageMode: configuration.languageMode)
                                let hasPriorPreview = self.activeSession?.latestPreviewText.isEmpty == false
                                if isMeaningfulRecognitionText(text, hasPriorPreview: hasPriorPreview) {
                                    // 仅用于展示实时预览文本；静音/停顿的结束判定改由能量 VAD 负责。
                                    self.activeSession?.latestPreviewText = text
                                    self.controller.updateRealtimeDraft(text)
                                    self.popup.updateDraft(text)
                                }
                            }
                            self.finishRealtimeSnapshot()
                        }
                    }
                }
            }
        }
    }

    private func finishRealtimeSnapshot() {
        realtimeBusy = false
        if let pending = pendingRealtimeSnapshot {
            pendingRealtimeSnapshot = nil
            if pending.taskID == activeSession?.id {
                transcribeRealtime(
                    taskID: pending.taskID,
                    url: pending.audioURL,
                    configuration: pending.configuration
                )
            } else {
                try? FileManager.default.removeItem(at: pending.audioURL)
            }
        }
    }

    private func handle(_ response: Result<[String: Any], Error>, task: RecordingTask) {
        let shouldUpdateInterface = shouldUpdateInterface(for: task.id)
        switch response {
        case .failure(let error):
            if shouldUpdateInterface {
                controller.setPrimaryStatus("识别失败", detail: error.localizedDescription, tone: .error, resetWaveform: true)
                popup.show(state: "识别失败", draft: "")
            }
            finishFinalTask(task)
        case .success(let value):
            if let error = value["error"] as? String, !error.isEmpty {
                if shouldUpdateInterface {
                    controller.setPrimaryStatus("识别失败", detail: error, tone: .error, resetWaveform: true)
                    popup.show(state: "识别失败", draft: "")
                }
                finishFinalTask(task)
                return
            }
            let text = cleanRecognitionText(value["text"] as? String ?? "", languageMode: task.configuration.languageMode)
            let elapsed = value["duration_sec"] as? Double ?? 0
            if isMeaningfulRecognitionText(text) {
                guard markFinalTaskForSubmission(task.id) else {
                    finishFinalTask(task)
                    return
                }
                if shouldUpdateInterface {
                    controller.updateRealtimeDraft(text)
                    let preference = controller.smartRewritePreference
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
                    } else {
                        if progress.shouldRewrite {
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
                                detail: String(format: "原文模式 · 本地识别耗时 %.2f 秒", elapsed),
                                tone: .success,
                                resetWaveform: true
                            )
                        }
                    }
                }
                if controller.autoTranslateEnabled {
                    rewriteTranslateAndSubmit(text, elapsed: elapsed, task: task)
                } else {
                    rewriteAndSubmit(text, elapsed: elapsed, task: task)
                }
            } else if shouldUpdateInterface {
                showEmptyRecording()
                finishFinalTask(task)
            } else {
                finishFinalTask(task)
            }
        }
    }

    private func rewriteTranslateAndSubmit(_ rawText: String, elapsed: Double, task: RecordingTask) {
        let preference = controller.smartRewritePreference
        let direction = controller.translationDirection
        let context = SmartInputContext(targetApp: currentTargetApp(for: task))
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
                rewriteResult = await self.smartInputRouter.rewrite(
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
                    sourceText: translation == nil ? nil : sourceForTranslation,
                    translatedText: translation?.translatedText,
                    translationDirection: translation?.direction,
                    usage: translation == nil ? rewriteResult.usage : SmartUsage.combined([rewriteResult.usage, translation?.usage])
                ))
            }
        }
    }

    private func rewriteAndSubmit(_ rawText: String, elapsed: Double, task: RecordingTask) {
        let preference = controller.smartRewritePreference
        let context = SmartInputContext(targetApp: currentTargetApp(for: task))
        Task { [weak self] in
            guard let self else { return }
            let result = await self.smartInputRouter.rewrite(
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
                    sourceText: nil,
                    translatedText: nil,
                    translationDirection: nil,
                    usage: result.usage
                ))
            }
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
        case .polish, .developerRequirement, .note, .chat, .exhaustiveSummary:
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

    private func translateWithTimeout(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        timeoutSeconds: TimeInterval
    ) async -> SmartTranslationOutput? {
        // 超时只放弃等待、不取消请求，让翻译后台跑完并把已计费的 usage 补记进账本，避免漏记与绕过成本上限。
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
            Task {
                if let late = try? await work.value {
                    SmartUsageLedgerStore.record(late.usage)
                }
            }
            return nil
        }
    }

    private func submitPasteResult(_ result: PendingPasteResult) {
        addRecentTranscription(for: result, completedAt: Date())
        SmartUsageLedgerStore.record(result.usage)
        pendingPasteResults.append(result)
        drainPendingPasteResultsIfPossible()
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
            return
        }
        if case .pasting = inputState {
            return
        }

        let result = pendingPasteResults.removeFirst()
        refreshTrackedTargetFromFrontmost()
        let pasteTarget = currentTargetApp(for: result.task)
        guard let pasteTarget else {
            skipAutomaticPaste(result)
            return
        }
        guard canPasteIntoFocusedElement(of: pasteTarget) else {
            skipAutomaticPaste(result, detail: "当前焦点不是明确的文本输入区，可在最近转录中复制")
            return
        }
        inputState = .pasting(result.task)
        pasteCoordinator.enqueue(text: result.text, targetApp: pasteTarget) { [weak self] outcome in
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
            popup.show(state: "已保存", draft: "")
            hidePopup(after: 1.0, task: task)
        }
        inputState = .idle
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
    }

    private func canPasteIntoFocusedElement(of targetApp: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return true }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success else {
            return false
        }
        guard let focusedElement = focusedValue else { return false }
        let element = focusedElement as! AXUIElement
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(element, &focusedPID) == .success,
              focusedPID == targetApp.processIdentifier else {
            return false
        }
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           isEditableTextRole(role) {
            return true
        }
        var isSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable) == .success,
           isSettable.boolValue {
            return true
        }
        return false
    }

    private func isEditableTextRole(_ role: String) -> Bool {
        role == kAXTextFieldRole as String ||
            role == kAXTextAreaRole as String ||
            role == kAXComboBoxRole as String
    }

    private func finishFinalTask(_ task: RecordingTask) {
        if case .finalizing(let current) = inputState, current.id == task.id {
            inputState = .idle
        }
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
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
            case .failed(let message):
                controller.setPrimaryStatus("自动粘贴失败", detail: message, tone: .error, resetWaveform: true)
                popup.show(state: "粘贴失败", draft: "")
                hidePopup(after: 1.2, task: task)
            }
        }
        if activeSession == nil, !recorder.isRecording {
            inputState = .idle
        }
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
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
            guard self?.shouldUpdateInterface(for: task.id) == true else { return }
            self?.popup.hideAnimated()
        }
    }

    private func shouldUpdateInterface(for taskID: UUID) -> Bool {
        taskID == latestSubmittedTaskID && !recorder.isRecording
    }

    private func markFinalTaskForSubmission(_ taskID: UUID) -> Bool {
        if completedFinalTaskIDs.contains(taskID) {
            LaunchDiagnostics.mark("final task ignored duplicate task_id=\(taskID.uuidString)")
            return false
        }
        completedFinalTaskIDs.insert(taskID)
        if completedFinalTaskIDs.count > 20, let first = completedFinalTaskIDs.first {
            completedFinalTaskIDs.remove(first)
        }
        return true
    }

    /// 每个音频缓冲都会调用：用 7 段能量峰值判断当前是否有人声，并据此触发静音/人离自动结束。
    /// 与 ASR 解耦，逐缓冲连续评估，确保每次打开胶囊都能稳定一致地识别静音。
    private func observeAudioEnergy(_ bands: [Float]) {
        guard recorder.isRecording else { return }
        let level = bands.max() ?? 0
        if level >= VAD.speechBandThreshold {
            voiceEverDetected = true
            lastVoiceAt = Date()
        }
        evaluateVADAutoFinish()
    }

    private func evaluateVADAutoFinish() {
        guard controller.autoFinishAfterPauseEnabled,
              activeSession?.activation != .hold,
              recorder.isRecording else { return }
        let now = Date()
        if voiceEverDetected {
            // 说过话之后，持续静音超过停顿时长 → 结束。
            guard let lastVoiceAt, now.timeIntervalSince(lastVoiceAt) >= Timing.autoFinishPauseSeconds else { return }
        } else {
            // 开场一直没人声（人离）→ 超过初始静音时长后结束。
            guard let recordingStartedAt, now.timeIntervalSince(recordingStartedAt) >= Timing.initialSilenceAutoFinishSeconds else { return }
        }
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        finishRecording()
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
