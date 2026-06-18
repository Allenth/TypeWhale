import AppKit
import Foundation

@MainActor
final class SpeechInputCoordinator {
    private enum Timing {
        static let autoFinishPauseSeconds: TimeInterval = 1.5
        static let initialSilenceAutoFinishSeconds: TimeInterval = 3.0
    }

    private let controller: MainViewController
    private let showMainWindow: () -> Void
    private let recorder = AudioRecorder()
    private let popup = RecordingPanel()
    private let hotkey = HotkeyMonitor()
    private let modelInstaller = SenseVoiceModelInstaller()
    private let nativeASR = NativeSenseVoiceBridge(runtimeName: "shared")
    private let outputAudioDucker = OutputAudioDucker()
    private lazy var asr = SenseVoiceRouter(runtimeName: "final", native: nativeASR)
    private lazy var realtimeASR = SenseVoiceRouter(runtimeName: "realtime", native: nativeASR)
    private let pasteCoordinator = PasteCoordinator()
    private var inputState: SpeechInputState = .idle
    private var activeSession: SpeechSession?
    private var pendingPasteResults: [PendingPasteResult] = []
    private var latestSubmittedTaskID: UUID?
    private var realtimeBusy = false
    private var pendingRealtimeSnapshot: RealtimeSnapshotRequest?
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

    init(controller: MainViewController, showMainWindow: @escaping () -> Void) {
        self.controller = controller
        self.showMainWindow = showMainWindow
    }

    func start() {
        recorder.onBands = { [weak self] bands in self?.popup.updateBands(bands) }
        recorder.onRealtimeSnapshot = { [weak self] taskID, url in
            self?.receiveRealtimeSnapshot(taskID: taskID, url: url)
        }
        controller.updateHotkeys(primary: primaryHotkeyBinding, secondary: secondaryHotkeyBinding)
        hotkey.update(primary: primaryHotkeyBinding, secondary: secondaryHotkeyBinding)
        hotkey.onDown = { [weak self] channel, binding in self?.handleHotkeyDown(channel: channel, binding: binding) }
        hotkey.onUp = { [weak self] channel, binding in self?.handleHotkeyUp(channel: channel, binding: binding) }
        modelInstaller.onStateChange = { [weak self] state in
            self?.controller.updateModelState(state)
            if case .ready = state {
                self?.nativeASR.reload()
                self?.controller.status.stringValue = "等待录音"
                self?.controller.detail.stringValue = "Fn 录音"
            }
        }
        controller.onInstallModel = { [weak self] in
            self?.modelInstaller.install()
        }
        controller.onHotkeysChange = { [weak self] primary, secondary in
            self?.primaryHotkeyBinding = primary
            self?.secondaryHotkeyBinding = secondary
            self?.hotkey.update(primary: primary, secondary: secondary)
            self?.refreshPermissions()
        }
        modelInstaller.refresh()
        hotkey.start()
        asr.start()
        realtimeASR.start()
        if let error = asr.startupError, SenseVoiceModelManifest.preferredModelDirectory == nil {
            controller.status.stringValue = "需要安装本地模型"
            controller.detail.stringValue = error
        }
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
        if globalListening {
            controller.hotkeyStatus.stringValue = "● 监听中"
            controller.hotkeyStatus.textColor = .systemGreen
        } else {
            controller.hotkeyStatus.stringValue = "● 未监听"
            controller.hotkeyStatus.textColor = .systemOrange
        }
    }

    private func handleHotkeyDown(channel: SpeechInputChannel, binding: HotkeyBinding) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }

    private func handleHotkeyUp(channel: SpeechInputChannel, binding: HotkeyBinding) {
        hotkeyIsPressed = false
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
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

    private func startRecording(
        instructions: String,
        activation: RecordingActivation,
        channel: SpeechInputChannel? = nil
    ) {
        guard !recorder.isRecording else { return }
        guard nativeASR.isAvailable else {
            controller.status.stringValue = "需要安装本地模型"
            controller.detail.stringValue = "请先在主窗口点击“安装模型”"
            showMainWindow()
            return
        }
        let realtimeEnabled = controller.realtimePreviewEnabled
        let taskID = UUID()
        let session = SpeechSession(
            id: taskID,
            targetApp: NSWorkspace.shared.frontmostApplication,
            configuration: ASRConfiguration(languageMode: .chinese),
            activation: activation,
            realtimeEnabled: realtimeEnabled,
            latestPreviewText: ""
        )
        activeSession = session
        inputState = .recording(taskID)
        controller.realtimeDraft.stringValue = realtimeEnabled ? "正在等待第一段实时文本…" : "胶囊实时预览已关闭"
        controller.status.stringValue = "录音中"
        controller.detail.stringValue = instructions
        popup.show(state: "录音中", draft: "")
        outputAudioDucker.duckIfNeeded(enabled: controller.duckSystemAudioWhileRecordingEnabled)
        do {
            try recorder.start(
                taskID: taskID,
                realtimeEnabled: realtimeEnabled,
                inputDeviceID: AudioInputDeviceProvider.selectedDeviceID()
            )
            scheduleInitialSilenceAutoFinishIfNeeded(for: taskID)
        } catch {
            cancelAutoFinishTimer()
            clearActiveRecording()
            controller.status.stringValue = "无法开始录音"
            controller.detail.stringValue = error.localizedDescription
            popup.show(state: "录音失败")
        }
    }

    private func finishRecording() {
        cancelAutoFinishTimer()
        guard let session = activeSession else { return }
        let taskID = session.id
        let configuration = session.configuration
        let targetApp = session.targetApp
        let result: (URL, TimeInterval)?
        do {
            result = try recorder.stop()
        } catch {
            clearActiveRecording()
            controller.status.stringValue = "保存录音失败"
            controller.detail.stringValue = error.localizedDescription
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
            duration: duration
        )
        inputState = .finalizing(task)
        latestSubmittedTaskID = taskID
        drainPendingPasteResultsIfPossible()
        controller.status.stringValue = "正在检测人声"
        controller.detail.stringValue = String(format: "已完整录制 %.1f 秒", duration)
        popup.hideAnimated()
        asr.containsSpeech(audio: url) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                let shouldUpdateInterface = self.shouldUpdateInterface(for: taskID)
                switch response {
                case .failure(let error):
                    if shouldUpdateInterface {
                        self.controller.status.stringValue = "人声检测失败"
                        self.controller.detail.stringValue = error.localizedDescription
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
                        self.controller.status.stringValue = "正在识别"
                        self.controller.detail.stringValue = String(format: "已完整录制 %.1f 秒", duration)
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
                                if !text.isEmpty {
                                    self.cancelInitialSilenceTimer()
                                    self.controller.realtimeDraft.stringValue = text
                                    self.popup.updateDraft(text)
                                    self.scheduleAutoFinishAfterPauseIfNeeded(text: text, taskID: taskID)
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
                controller.status.stringValue = "识别失败"
                controller.detail.stringValue = error.localizedDescription
                popup.show(state: "识别失败", draft: "")
            }
            finishFinalTask(task)
        case .success(let value):
            if let error = value["error"] as? String, !error.isEmpty {
                if shouldUpdateInterface {
                    controller.status.stringValue = "识别失败"
                    controller.detail.stringValue = error
                    popup.show(state: "识别失败", draft: "")
                }
                finishFinalTask(task)
                return
            }
            let text = cleanRecognitionText(value["text"] as? String ?? "", languageMode: task.configuration.languageMode)
            let elapsed = value["duration_sec"] as? Double ?? 0
            if shouldUpdateInterface {
                if !text.isEmpty {
                    controller.addRecentTranscription(text, recognitionSeconds: elapsed)
                    controller.realtimeDraft.stringValue = text
                }
                controller.status.stringValue = "识别完成"
                controller.detail.stringValue = String(format: "本地识别耗时 %.2f 秒", elapsed)
            }
            if !text.isEmpty {
                if shouldUpdateInterface {
                    popup.hideAnimated()
                }
                submitPasteResult(PendingPasteResult(task: task, text: text, recognitionSeconds: elapsed))
            } else if shouldUpdateInterface {
                popup.hideAnimated()
                finishFinalTask(task)
            } else {
                finishFinalTask(task)
            }
        }
    }

    private func submitPasteResult(_ result: PendingPasteResult) {
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
        inputState = .pasting(result.task)
        pasteCoordinator.enqueue(text: result.text, targetApp: result.task.targetApp) { [weak self] outcome in
            self?.handlePasteOutcome(outcome, task: result.task)
        }
    }

    private func finishFinalTask(_ task: RecordingTask) {
        if case .finalizing(let current) = inputState, current.id == task.id {
            inputState = .idle
        }
        drainPendingPasteResultsIfPossible()
    }

    private func showEmptyRecording() {
        controller.status.stringValue = "没有收到有效音频"
        controller.detail.stringValue = emptyRecordingDetail()
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

    private func handlePasteOutcome(_ outcome: PasteOutcome, task: RecordingTask) {
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
                controller.status.stringValue = "自动粘贴失败"
                controller.detail.stringValue = message
                popup.show(state: "粘贴失败", draft: "")
                hidePopup(after: 1.2, task: task)
            }
        }
        if activeSession == nil, !recorder.isRecording {
            inputState = .idle
        }
        drainPendingPasteResultsIfPossible()
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

    private func scheduleAutoFinishAfterPauseIfNeeded(text: String, taskID: UUID) {
        guard activeSession?.id == taskID,
              text != activeSession?.latestPreviewText else { return }
        activeSession?.latestPreviewText = text
        scheduleAutoFinishAfterPause(for: taskID)
    }

    private func scheduleInitialSilenceAutoFinishIfNeeded(for taskID: UUID) {
        guard controller.autoFinishAfterPauseEnabled,
              activeSession?.activation != .hold,
              recorder.isRecording,
              taskID == activeSession?.id else { return }
        initialSilenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeSession?.activation != .hold,
                  self.recorder.isRecording,
                  self.activeSession?.id == taskID,
                  self.activeSession?.latestPreviewText.isEmpty == true else { return }
            self.suppressNextHotkeyUp = self.hotkeyIsPressed
            self.hotkeyIsPressed = false
            self.finishRecording()
        }
        initialSilenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.initialSilenceAutoFinishSeconds, execute: workItem)
    }

    private func scheduleAutoFinishAfterPause(for taskID: UUID) {
        guard controller.autoFinishAfterPauseEnabled,
              activeSession?.activation != .hold,
              recorder.isRecording,
              taskID == activeSession?.id else { return }
        autoFinishWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeSession?.activation != .hold,
                  self.recorder.isRecording,
                  self.activeSession?.id == taskID else { return }
            self.suppressNextHotkeyUp = self.hotkeyIsPressed
            self.hotkeyIsPressed = false
            self.finishRecording()
        }
        autoFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.autoFinishPauseSeconds, execute: workItem)
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
