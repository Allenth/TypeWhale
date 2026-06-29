import AppKit
import Foundation

@MainActor
final class SpeechInputCoordinator {
    private enum Timing {
        static let autoFinishPauseSeconds: TimeInterval = 1.5
        static let initialSilenceAutoFinishSeconds: TimeInterval = 3.0
        static let holdToRecordSeconds: TimeInterval = 0.28
        /// 单次录音硬上限：超过即自动结束并识别，封住异常长录音的能耗和内存峰值。
        /// 历史 1.2 版本已验证一两分钟口述可用，不应把 45 秒后的当前回归误判为模型时长上限。
        static let maxRecordingSeconds: TimeInterval = 360
        /// 录音中持续无语音/文字产出的上限：已说过话则自动收尾保存，从未说话则取消空录音。
        static let noTextTimeoutSeconds: TimeInterval = 300
        static let backgroundHealthSeconds: TimeInterval = 30
        static let recordingSafetySeconds: TimeInterval = 1
        static let capsuleStatusSeconds: TimeInterval = 1
        static let memorySafetyCheckSeconds: TimeInterval = 30
        static let wakeRecoveryGraceSeconds: TimeInterval = 3
        static let realtimeSnapshotTimeoutSeconds: TimeInterval = 3
    }

    private var recordingStartedAt: Date?
    private var lastCapsuleStatusUpdateAt: Date?
    private var lastVoiceAt: Date?
    private var voiceEverDetected = false
    /// 本轮人声检测（Silero）是否可用；Silero 探测出错时置 false → 停顿自动结束随之停用，
    /// 仅保留手动停止与硬上限，避免误判成"一直没人声"而过早结束。
    private var voiceDetectionAvailable = false
    private var voiceProbeInFlight = false

    private let controller: MainViewController
    private let showMainWindow: () -> Void
    private let hideMainWindow: () -> Void
    private let shouldKeepMainWindowVisibleForScreenshot: () -> Bool
    private let recorder = AudioRecorder()
    private let popup = RecordingPanel()
    private let hotkey = HotkeyMonitor()
    private let modelInstaller = SenseVoiceModelInstaller()
    private let nativeASR = NativeSenseVoiceBridge(runtimeName: "shared")
    /// 专用于 Silero VAD 的独立桥接：所有 VAD 调用（实时探测 + 末尾人声闸门）都走它自己的串行队列，
    /// 不再和慢速 SenseVoice 重识别抢同一条队列被饿死；全局 g_cached_vad 也因此只被一条队列访问，无竞争。
    private let vadBridge = NativeSenseVoiceBridge(runtimeName: "vad")
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
    /// 块最终快照的待处理队列：绝不丢弃（丢了会整块预览文本消失），优先于普通中间快照处理。
    private var pendingFinalSnapshots: [RealtimeSnapshotRequest] = []
    private var activeRealtimeSnapshotID: UUID?
    private var realtimeSnapshotTimeoutWorkItem: DispatchWorkItem?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var trackedTargetTaskID: UUID?
    private var trackedTargetApp: NSRunningApplication?
    private var hotkeyIsPressed = false
    private var longPressWorkItem: DispatchWorkItem?
    private var autoFinishWorkItem: DispatchWorkItem?
    private var initialSilenceWorkItem: DispatchWorkItem?
    private var idleASRUnloadWorkItem: DispatchWorkItem?
    private var backgroundHealthTimer: Timer?
    private var recordingSafetyTimer: Timer?
    private var capsuleStatusTimer: Timer?
    private var lastMemorySafetyCheckAt = Date.distantPast
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

    init(
        controller: MainViewController,
        showMainWindow: @escaping () -> Void,
        hideMainWindow: @escaping () -> Void,
        shouldKeepMainWindowVisibleForScreenshot: @escaping () -> Bool
    ) {
        self.controller = controller
        self.showMainWindow = showMainWindow
        self.hideMainWindow = hideMainWindow
        self.shouldKeepMainWindowVisibleForScreenshot = shouldKeepMainWindowVisibleForScreenshot
    }

    func start() {
        recorder.onBands = { [weak self] bands in
            self?.popup.updateBands(bands)
            self?.controller.updateInputBands(bands)
            self?.tickRecordingGuards()
            self?.refreshCapsuleStatusIfNeeded()
        }
        recorder.onVoiceProbe = { [weak self] samples, sampleRate in
            self?.receiveVoiceProbe(samples: samples, sampleRate: sampleRate)
        }
        recorder.onInputLevelDb = { [weak self] db in
            self?.popup.updateInputLevel(db: db)
        }
        recorder.onRealtimeSnapshot = { [weak self] taskID, url, chunkIndex, isChunkFinal, reachedNearField in
            self?.receiveRealtimeSnapshot(
                taskID: taskID, url: url, chunkIndex: chunkIndex,
                isChunkFinal: isChunkFinal, reachedNearField: reachedNearField
            )
        }
        recorder.onInputRouteChanged = { [weak self] message in
            self?.handleAudioInputRouteChanged(message)
        }
        controller.updateHotkeys(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            secondaryScreenshot: secondaryScreenshotHotkeyBinding,
            screenshotTranslation: screenshotTranslationHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding
        )
        hotkey.update(
            primary: primaryHotkeyBinding,
            secondary: secondaryHotkeyBinding,
            screenshot: screenshotHotkeyBinding,
            secondaryScreenshot: secondaryScreenshotHotkeyBinding,
            screenshotTranslation: screenshotTranslationHotkeyBinding,
            autoTranslate: autoTranslateHotkeyBinding,
            mainWindow: mainWindowHotkeyBinding
        )
        hotkey.onDown = { [weak self] channel, binding in self?.handleHotkeyDown(channel: channel, binding: binding) }
        hotkey.onUp = { [weak self] channel, binding in self?.handleHotkeyUp(channel: channel, binding: binding) }
        hotkey.onAutoTranslateToggle = { [weak self] in self?.toggleAutoTranslateFromHotkey() }
        hotkey.onScreenshot = { [weak self] in self?.beginScreenshotFromHotkey() }
        hotkey.onScreenshotTranslation = { [weak self] in self?.beginScreenshotTranslationFromHotkey() }
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
                self?.releaseASRResourcesIfMemoryElevated()
            }
        }
        controller.onInstallModel = { [weak self] in
            self?.modelInstaller.install()
        }
        controller.onHotkeysChange = { [weak self] primary, secondary, screenshot, secondaryScreenshot, screenshotTranslation, autoTranslate, mainWindow in
            self?.primaryHotkeyBinding = primary
            self?.secondaryHotkeyBinding = secondary
            self?.screenshotHotkeyBinding = screenshot
            self?.secondaryScreenshotHotkeyBinding = secondaryScreenshot
            self?.screenshotTranslationHotkeyBinding = screenshotTranslation
            self?.autoTranslateHotkeyBinding = autoTranslate
            self?.mainWindowHotkeyBinding = mainWindow
            self?.hotkey.update(
                primary: primary,
                secondary: secondary,
                screenshot: screenshot,
                secondaryScreenshot: secondaryScreenshot,
                screenshotTranslation: screenshotTranslation,
                autoTranslate: autoTranslate,
                mainWindow: mainWindow
            )
            LaunchDiagnostics.mark("hotkey_update")
            self?.hotkey.start()
            self?.refreshPermissions()
        }
        modelInstaller.refresh()
        LaunchDiagnostics.mark("hotkey_start reason=app_start")
        hotkey.start()
        asr.start()
        realtimeASR.start()
        releaseASRResourcesIfMemoryElevated()
        startObservingTargetApplicationChanges()
        refreshPermissions()
        PermissionDiagnosticsProvider.requestAccessibilityIfNeeded()
        startBackgroundHealthTimer()
        PermissionDiagnosticsProvider.requestMicrophone { [weak self] in self?.refreshPermissions() }
    }

    func stop() {
        stopBackgroundHealthTimer()
        stopRecordingSafetyTimer()
        longPressWorkItem?.cancel()
        cancelAutoFinishTimer()
        cancelInitialSilenceTimer()
        cancelIdleASRUnload()
        recorder.cancel()
        clearActiveRecording()
        pendingPasteResults.removeAll()
        inputState = .idle
        stopObservingTargetApplicationChanges()
        asr.stop()
        realtimeASR.stop()
    }

    func handleSystemWillPowerOff() {
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_will_power_off"))
        cancelRecordingForSystemSleep(reason: "power_off")
    }

    func handleSystemWillSleep() {
        isSystemSleeping = true
        wakeRecoveryUntil = nil
        stopBackgroundHealthTimer()
        stopRecordingSafetyTimer()
        stopCapsuleStatusTimer()
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_will_sleep"))
        cancelRecordingForSystemSleep(reason: "sleep")
    }

    func handleSystemDidWake() {
        isSystemSleeping = false
        wakeRecoveryUntil = Date().addingTimeInterval(Timing.wakeRecoveryGraceSeconds)
        didFlushASRArenaForElevatedMemory = false
        didLogWakeRecoveryReloadSkip = false
        LaunchDiagnostics.mark(backgroundStateLogLine(event: "system_did_wake"))
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.wakeRecoveryGraceSeconds) { [weak self] in
            guard let self, !self.isSystemSleeping else { return }
            self.wakeRecoveryUntil = nil
            LaunchDiagnostics.mark(self.backgroundStateLogLine(event: "wake_recovery_check"))
            self.refreshPermissions()
            if !self.hotkey.isGlobalListening {
                LaunchDiagnostics.mark("hotkey_start reason=wake_recovery")
                self.hotkey.start()
            }
            self.controller.updateMemoryReadout()
            self.startBackgroundHealthTimer()
        }
    }

    func refreshUserVisibleDiagnostics() {
        refreshPermissions()
        controller.updateMemoryReadout()
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
        hotkeyIsPressed = false
        suppressNextHotkeyUp = true
        if recorder.isRecording || activeSession != nil {
            LaunchDiagnostics.mark("recording_safety_cancel reason=\(reason)")
            recorder.cancel()
            clearActiveRecording()
            trackedTargetTaskID = nil
            trackedTargetApp = nil
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
        // 只有遇到有效可粘贴目标才更新；瞬时非粘贴前台（TypeWhale 自身胶囊/窗口、桌面等）
        // 不清空已知的好目标，避免「识别成功却找不到粘贴目标」。
        if let target = pasteableTargetApp(app) {
            trackedTargetApp = target
            if var session = activeSession, session.id == trackedTargetTaskID {
                session.targetApp = target
                activeSession = session
            }
        }
        let display = trackedTargetApp ?? app
        popup.updateTargetApp(
            appIcon: display?.icon,
            appName: displayNameForSelectedTarget(display)
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
        if binding.kind == .mediaPlay {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            hotkeyIsPressed = false
            if activeSession != nil || recorder.isRecording {
                finishRecording()
            } else {
                startRecording(
                    instructions: "再次按 \(binding.displayName) 完成录音",
                    activation: .toggle,
                    channel: channel
                )
            }
            return
        }
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
        showMainWindow()
    }

    private func cycleSmartRewriteModeFromCapsule() {
        let next = controller.cycleSmartRewritePreference()
        popup.updateModeName(next.displayName)
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
            let remaining = max(0, Int((Timing.maxRecordingSeconds - Date().timeIntervalSince(startedAt)).rounded()))
            popup.updateRecordingStatus(remainingSeconds: remaining, memoryHigh: memoryHigh)
        } else {
            popup.updateRecordingStatus(remainingSeconds: nil, memoryHigh: memoryHigh)
        }
    }

    private func beginScreenshotFromHotkey() {
        beginScreenshotFromHotkey(translateAfterSelection: false)
    }

    private func beginScreenshotTranslationFromHotkey() {
        beginScreenshotFromHotkey(translateAfterSelection: true)
    }

    private func beginScreenshotFromHotkey(translateAfterSelection: Bool) {
        guard activeSession == nil, !recorder.isRecording else { return }
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        hotkeyIsPressed = false
        if !shouldKeepMainWindowVisibleForScreenshot() {
            hideMainWindow()
        }
        if translateAfterSelection {
            screenshotCoordinator.beginTranslation()
        } else {
            screenshotCoordinator.begin()
        }
    }

    private func startRecording(
        instructions: String,
        activation: RecordingActivation,
        channel: SpeechInputChannel? = nil
    ) {
        guard !recorder.isRecording else { return }
        cancelIdleASRUnload()
        discardPendingRealtimeSnapshot()
        didFlushASRArenaForElevatedMemory = false
        startRecordingSafetyTimer()
        startCapsuleStatusTimer()
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
                inputDeviceID: AudioInputDeviceProvider.selectedDeviceID(),
                voiceProcessingEnabled: controller.micVoiceProcessingEnabled
            )
            recordingStartedAt = Date()
            lastCapsuleStatusUpdateAt = nil
            updateCapsuleStatus()
            lastVoiceAt = nil
            voiceEverDetected = false
            voiceProbeInFlight = false
            // Silero VAD 随 app 内置，正常情况下始终可用；探测出错时会在 receiveVoiceProbe 里置 false。
            voiceDetectionAvailable = vadBridge.isVoiceActivityDetectionAvailable
            LaunchDiagnostics.mark(
                "recording_start task_id=\(taskID.uuidString) activation=\(activation) realtime=\(realtimeEnabled) voice_detect=\(voiceDetectionAvailable ? "silero" : "off")"
            )
        } catch {
            LaunchDiagnostics.mark("recording_start_failed error=\(error.localizedDescription)")
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
            LaunchDiagnostics.mark("recording_finish_requested task_id=\(taskID.uuidString)")
            result = try recorder.stop()
        } catch {
            LaunchDiagnostics.mark("recording_stop_failed task_id=\(taskID.uuidString) error=\(error.localizedDescription)")
            clearActiveRecording()
            controller.setPrimaryStatus("保存录音失败", detail: error.localizedDescription, tone: .error, resetWaveform: true)
            popup.show(state: "保存失败", draft: "")
            return
        }
        clearActiveRecording()
        guard let (url, duration) = result else {
            LaunchDiagnostics.mark("recording_finish_empty task_id=\(taskID.uuidString)")
            inputState = .idle
            drainPendingPasteResultsIfPossible()
            showEmptyRecording()
            releaseASRResourcesIfMemoryElevated()
            return
        }
        LaunchDiagnostics.mark(
            "recording_finish_saved task_id=\(taskID.uuidString) duration_ms=\(Int(duration * 1000)) url=\(url.lastPathComponent)"
        )
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
        vadBridge.containsSpeech(audio: url) { [weak self] response in
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
        stopRecordingSafetyTimer()
        stopCapsuleStatusTimer()
        activeSession = nil
        recordingStartedAt = nil
        lastCapsuleStatusUpdateAt = nil
        updateCapsuleStatus()
        controller.resetInputBands()
        discardPendingRealtimeSnapshot()
        if !isSystemSleeping {
            startBackgroundHealthTimer()
        }
    }

    private func handleAudioInputRouteChanged(_ message: String) {
        guard activeSession != nil || recorder.isRecording else { return }
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        LaunchDiagnostics.mark("recording_safety_cancel reason=input_route_changed message=\(message)")
        recorder.cancel()
        clearActiveRecording()
        trackedTargetTaskID = nil
        trackedTargetApp = nil
        inputState = .idle
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
        controller.setPrimaryStatus(
            "麦克风已切换",
            detail: "\(message)已停止本次录音，请重新按快捷键开始。",
            tone: .warning,
            resetWaveform: true
        )
        popup.show(state: "麦克风已切换", draft: "请重新录音")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.popup.hideAnimated()
        }
    }

    private func discardPendingRealtimeSnapshot() {
        if let pendingRealtimeSnapshot {
            try? FileManager.default.removeItem(at: pendingRealtimeSnapshot.audioURL)
        }
        pendingRealtimeSnapshot = nil
        for pendingFinal in pendingFinalSnapshots {
            try? FileManager.default.removeItem(at: pendingFinal.audioURL)
        }
        pendingFinalSnapshots.removeAll()
        realtimeBusy = false
        activeRealtimeSnapshotID = nil
        realtimeSnapshotTimeoutWorkItem?.cancel()
        realtimeSnapshotTimeoutWorkItem = nil
    }

    private func receiveRealtimeSnapshot(taskID: UUID, url: URL, chunkIndex: Int, isChunkFinal: Bool, reachedNearField: Bool) {
        guard let session = activeSession, taskID == session.id else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let request = RealtimeSnapshotRequest(
            taskID: taskID,
            audioURL: url,
            configuration: session.configuration,
            chunkIndex: chunkIndex,
            isChunkFinal: isChunkFinal,
            reachedNearField: reachedNearField
        )
        if realtimeBusy {
            if isChunkFinal {
                // 块最终快照绝不丢弃，进专用队列。
                pendingFinalSnapshots.append(request)
            } else {
                // 普通中间快照只保留最新一帧（合并旧的）。
                if let pendingRealtimeSnapshot {
                    try? FileManager.default.removeItem(at: pendingRealtimeSnapshot.audioURL)
                }
                pendingRealtimeSnapshot = request
            }
            return
        }
        transcribeRealtime(request)
    }

    private func transcribeRealtime(_ request: RealtimeSnapshotRequest) {
        let snapshotID = UUID()
        let taskID = request.taskID
        let url = request.audioURL
        activeRealtimeSnapshotID = snapshotID
        realtimeBusy = true
        scheduleRealtimeSnapshotTimeout(snapshotID: snapshotID, taskID: taskID, url: url)
        realtimeASR.transcribe(
            audio: url,
            configuration: request.configuration
        ) { [weak self] response in
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: url)
                guard let self else { return }
                guard self.activeRealtimeSnapshotID == snapshotID else { return }
                self.applyRealtimePreview(request: request, response: response)
                self.finishRealtimeSnapshot(snapshotID: snapshotID)
            }
        }
    }

    /// 把某个块快照的识别结果合并进预览：committedPreviewText（冻结前缀）+ 当前块尾巴。
    /// 块最终快照会把尾巴冻结进 committedPreviewText，从此不再变动（稳定、不跳变）。
    private func applyRealtimePreview(request: RealtimeSnapshotRequest, response: Result<[String: Any], Error>) {
        guard var session = activeSession, request.taskID == session.id else { return }
        // 已提交块的滞后快照直接丢弃，不污染显示。
        guard request.chunkIndex >= session.currentChunkIndex else { return }

        // 近场门：未达到近场响度的块（远场/弱信号）不接受其文本，尾巴保持为空。
        if request.reachedNearField,
           case .success(let value) = response, (value["error"] as? String ?? "").isEmpty {
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
        popup.updateDraft(display)
        let elapsedMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        LaunchDiagnostics.mark(
            "realtime_preview_update task_id=\(request.taskID.uuidString) elapsed_ms=\(elapsedMs) chunk=\(request.chunkIndex) final=\(request.isChunkFinal) chars=\(display.count)"
        )
    }

    private func scheduleRealtimeSnapshotTimeout(snapshotID: UUID, taskID: UUID, url: URL) {
        realtimeSnapshotTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeRealtimeSnapshotID == snapshotID else { return }
            LaunchDiagnostics.mark(
                "realtime_snapshot_timeout task_id=\(taskID.uuidString) seconds=\(Int(Timing.realtimeSnapshotTimeoutSeconds))"
            )
            try? FileManager.default.removeItem(at: url)
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
    }

    private func dispatchPendingRealtime(_ request: RealtimeSnapshotRequest) {
        if request.taskID == activeSession?.id {
            transcribeRealtime(request)
        } else {
            try? FileManager.default.removeItem(at: request.audioURL)
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
            let engine = value["engine"] as? String ?? "--"
            LaunchDiagnostics.mark(
                "final_asr_result task_id=\(task.id.uuidString) audio_duration_ms=\(Int(task.duration * 1000)) recognition_ms=\(Int(elapsed * 1000)) chars=\(text.count) engine=\(engine)"
            )
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
                    rawText: rawText,
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
        let context = SmartInputContext(
            targetApp: currentTargetApp(for: task),
            recordingSessionId: task.id.uuidString
        )
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
                    rawText: rawText,
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
        saveBacklogIfRequested(result)
        SmartUsageLedgerStore.record(result.usage)
        pendingPasteResults.append(result)
        drainPendingPasteResultsIfPossible()
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
        refreshTrackedTargetFromFrontmost()
        let pasteTarget = currentTargetApp(for: result.task)
        LaunchDiagnostics.mark(
            "paste_drain task_id=\(result.task.id.uuidString.prefix(8)) target=\(pasteTarget?.localizedName ?? "nil") frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil") fallback=\(result.task.targetApp?.localizedName ?? "nil")"
        )
        guard let pasteTarget else {
            skipAutomaticPaste(result)
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
            hidePopup(after: 0, task: task)
        }
        inputState = .idle
        endTargetTrackingIfNeeded(task.id)
        drainPendingPasteResultsIfPossible()
        releaseASRResourcesIfMemoryElevated()
    }

    private func finishFinalTask(_ task: RecordingTask) {
        if case .finalizing(let current) = inputState, current.id == task.id {
            inputState = .idle
        }
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
                hidePopup(after: 0, task: task)
            }
        }
        if activeSession == nil, !recorder.isRecording {
            inputState = .idle
        }
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

    private var isIdleForASRResourceRelease: Bool {
        if activeSession != nil || recorder.isRecording || !pendingPasteResults.isEmpty || realtimeBusy {
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

    /// 每个音频缓冲触发一次：推进时间相关的录音守卫（硬上限、无声超时），并高频评估停顿自动结束。
    /// 人声判定本身由 receiveVoiceProbe（Silero）负责，这里不再做任何能量阈值判断。
    private func tickRecordingGuards() {
        guard recorder.isRecording else { return }
        if enforceMaxRecordingDuration() { return }
        if enforceNoTextTimeout() { return }
        evaluateVADAutoFinish()
    }

    /// 人声门控核心：录音过程中约每 0.4s 收到一段最近窗口 PCM，交给 Silero 判定当前是否有人声。
    /// 本方法在 main 上被调用（recorder 已派发）；原生 VAD 在其专用串行队列上跑，完成后回到 main 更新状态。
    private func receiveVoiceProbe(samples: [Float], sampleRate: Int) {
        guard voiceDetectionAvailable, recorder.isRecording, !voiceProbeInFlight else { return }
        let capturedAt = Date()
        voiceProbeInFlight = true
        vadBridge.containsSpeech(samples: samples, sampleRate: sampleRate) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.voiceProbeInFlight = false
                guard self.recorder.isRecording else { return }
                switch result {
                case .success(true):
                    self.voiceEverDetected = true
                    self.lastVoiceAt = capturedAt
                    // 有人声 → 通知录音器：当前不宜在此切块（避免切词）。
                    self.recorder.updateRealtimeVoiceActive(true)
                    self.evaluateVADAutoFinish()
                case .success(false):
                    // 停顿 → 录音器可在此处对齐分块边界并冻结提交。
                    self.recorder.updateRealtimeVoiceActive(false)
                case .failure:
                    // Silero 实时检测出错 → 停用人声检测：关闭停顿自动结束，仅保留手动停止与硬上限。
                    // 同时让分块回到「硬上限驱动」（视为一直有人声，不在停顿处切）。
                    self.voiceDetectionAvailable = false
                    self.recorder.updateRealtimeVoiceActive(true)
                    LaunchDiagnostics.mark("vad_probe_unavailable")
                }
            }
        }
    }

    /// 录音超过单次硬上限时自动结束并识别，封住 ASR 内存峰值。返回是否已触发结束。
    private func enforceRecordingTimeoutsIfNeeded() {
        guard recorder.isRecording || activeSession != nil else { return }
        if recorder.isRecording, activeSession == nil {
            LaunchDiagnostics.mark("recording_safety_cancel reason=missing_session")
            recorder.cancel()
            clearActiveRecording()
            trackedTargetTaskID = nil
            trackedTargetApp = nil
            inputState = .idle
            drainPendingPasteResultsIfPossible()
            return
        }
        if enforceMaxRecordingDuration() { return }
        if enforceNoTextTimeout() { return }
    }

    /// 录音超过单次硬上限时自动结束并识别，封住异常长录音的能耗和内存峰值。返回是否已触发结束。
    private func enforceMaxRecordingDuration() -> Bool {
        guard let startedAt = recordingStartedAt,
              Date().timeIntervalSince(startedAt) >= Timing.maxRecordingSeconds else { return false }
        let durationText = Self.formatMaxRecordingDuration(Timing.maxRecordingSeconds)
        LaunchDiagnostics.mark("recording_auto_finish reason=max_duration seconds=\(Int(Timing.maxRecordingSeconds))")
        controller.setPrimaryStatus(
            "已达单次最长录音",
            detail: "单次最长约 \(durationText)，已自动结束并开始识别",
            tone: .warning,
            resetWaveform: false
        )
        suppressNextHotkeyUp = hotkeyIsPressed
        hotkeyIsPressed = false
        finishRecording()
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
            finishRecording()
            return true
        }
        recorder.cancel()
        clearActiveRecording()
        trackedTargetTaskID = nil
        trackedTargetApp = nil
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

    private func evaluateVADAutoFinish() {
        // 人声检测不可用时（Silero 探测出错）停用停顿自动结束，避免误判成"一直没人声"过早结束。
        guard voiceDetectionAvailable,
              controller.autoFinishAfterPauseEnabled,
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
