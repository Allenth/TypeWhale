import Foundation

final class RemoteInputCoordinator {
    typealias BeginSpeech = (Int) -> UUID?
    typealias AppendPCM = ([Int16], UUID) -> Void
    typealias EndSpeech = (UUID) -> Void
    typealias CancelSpeech = (UUID) -> Void

    var onSnapshot: ((RemoteInputSnapshot) -> Void)?

    private let bluetooth: RemoteBluetoothController
    private let hid: RemoteHIDMonitor
    private let beginSpeech: BeginSpeech
    private let appendPCM: AppendPCM
    private let endSpeech: EndSpeech
    private let cancelSpeech: CancelSpeech
    private let speechPipelineIsBusy: () -> Bool
    private let settingsStore: RemoteInputSettingsStore
    private let actionDispatcher: RemoteButtonActionDispatcher
    private let powerKeyNeutralizer: RemotePowerKeyNeutralizer
    private var remoteSessionPolicy = RemoteSpeechSessionPolicy()
    private var actionCycleTracker = RemoteButtonActionCycleTracker()
    private var snapshot: RemoteInputSnapshot
    private var started = false
    private var processingPollGeneration = 0

    var isEnabled: Bool {
        snapshot.enabled
    }

    init(
        bluetooth: RemoteBluetoothController = RemoteBluetoothController(),
        hid: RemoteHIDMonitor = RemoteHIDMonitor(),
        beginSpeech: @escaping BeginSpeech,
        appendPCM: @escaping AppendPCM,
        endSpeech: @escaping EndSpeech,
        cancelSpeech: @escaping CancelSpeech,
        speechPipelineIsBusy: @escaping () -> Bool,
        showMainWindow: @escaping () -> Void,
        send: @escaping () -> Bool,
        cancelCurrentOperation: @escaping () -> Void,
        settingsStore: RemoteInputSettingsStore = RemoteInputSettingsStore(),
        actionDispatcher: RemoteButtonActionDispatcher? = nil,
        powerKeyNeutralizer: RemotePowerKeyNeutralizer = RemotePowerKeyNeutralizer()
    ) {
        self.bluetooth = bluetooth
        self.hid = hid
        self.beginSpeech = beginSpeech
        self.appendPCM = appendPCM
        self.endSpeech = endSpeech
        self.cancelSpeech = cancelSpeech
        self.speechPipelineIsBusy = speechPipelineIsBusy
        self.settingsStore = settingsStore
        self.powerKeyNeutralizer = powerKeyNeutralizer
        self.actionDispatcher = actionDispatcher ?? RemoteButtonActionDispatcher(
            showMainWindow: showMainWindow,
            send: send,
            cancelCurrentOperation: cancelCurrentOperation,
            emitKeyboardAction: RemoteKeyboardActionEmitter().emit
        )
        snapshot = RemoteInputSnapshot(
            enabled: settingsStore.loadEnabled(),
            phase: .disabled,
            bluetoothPermission: .unknown,
            inputMonitoringPermission: .unknown,
            device: RemoteDeviceSnapshot(),
            pipeline: RemoteVoicePipelineSnapshot(),
            mappings: settingsStore.loadMappings(),
            pressedButton: nil
        )
    }

    func start() {
        guard !started else { return }
        started = true
        wireCallbacks()
        _ = synchronizePowerKeyNeutralization()
        synchronizeHIDMonitoring()
        snapshot.inputMonitoringPermission = hid.permissionStatus
        bluetooth.start(enabled: snapshot.enabled)
        publish()
    }

    func stop() {
        guard started else { return }
        started = false
        processingPollGeneration += 1
        _ = powerKeyNeutralizer.setNeutralized(false)
        bluetooth.stop()
        hid.stop()
        actionCycleTracker.reset()
        if let taskID = remoteSessionPolicy.cancel() {
            cancelSpeech(taskID)
        }
    }

    func suspend() {
        guard started else { return }
        processingPollGeneration += 1
        _ = powerKeyNeutralizer.setNeutralized(false)
        bluetooth.stop()
        hid.stop()
        actionCycleTracker.reset()
    }

    func resume() {
        guard started else { return }
        _ = synchronizePowerKeyNeutralization()
        synchronizeHIDMonitoring()
        bluetooth.start(enabled: snapshot.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        snapshot.enabled = enabled
        settingsStore.saveEnabled(enabled)
        _ = synchronizePowerKeyNeutralization()
        bluetooth.setEnabled(enabled)
        synchronizeHIDMonitoring()
        publish()
    }

    private func synchronizeHIDMonitoring() {
        if snapshot.enabled {
            hid.start()
        } else {
            hid.stop()
        }
    }

    func performPrimaryAction() {
        switch snapshot.phase {
        case .scanning:
            bluetooth.stopScan()
        case .disabled:
            setEnabled(true)
        default:
            bluetooth.scan()
        }
    }

    func setAction(_ action: RemoteButtonAction, for button: RemoteButton) {
        var candidate = snapshot.mappings
        candidate.set(action, for: button)
        if button == .power {
            let shouldNeutralize = snapshot.enabled &&
                candidate.binding(for: .power).replacesSystemEvent
            guard powerKeyNeutralizer.setNeutralized(shouldNeutralize) else {
                let actionID = candidate.binding(for: button).actionID.rawValue
                LaunchDiagnostics.mark(
                    "remote_power_mapping_changed=false action=\(actionID) reason=neutralization_failed"
                )
                publish()
                return
            }
        }
        snapshot.mappings = candidate
        settingsStore.saveMappings(candidate)
        publish()
    }

    func resetMappings() {
        var defaults = RemoteButtonMapping.defaults
        if snapshot.enabled,
           !powerKeyNeutralizer.setNeutralized(false) {
            defaults.set(snapshot.mappings.action(for: .power), for: .power)
            LaunchDiagnostics.mark(
                "remote_power_mapping_reset=false reason=restore_failed"
            )
        }
        snapshot.mappings = defaults
        settingsStore.saveMappings(snapshot.mappings)
        publish()
    }

    private func wireCallbacks() {
        hid.shouldSuppressSystemEvent = { [weak self] button in
            guard let self else { return false }
            let binding = self.snapshot.mappings.binding(for: button)
            if button == .power {
                return binding.replacesSystemEvent && self.powerKeyNeutralizer.isNeutralized
            }
            return binding.replacesSystemEvent
        }
        bluetooth.onSnapshot = { [weak self] bluetoothSnapshot in
            guard let self else { return }
            self.snapshot.phase = bluetoothSnapshot.phase
            self.snapshot.bluetoothPermission = bluetoothSnapshot.bluetoothPermission
            self.snapshot.device = bluetoothSnapshot.device
            self.snapshot.pipeline = bluetoothSnapshot.pipeline
            if bluetoothSnapshot.device.name != nil {
                _ = self.synchronizePowerKeyNeutralization()
            }
            self.publish()
        }
        bluetooth.onVoiceStart = { [weak self] sampleRate in
            guard let self,
                  self.actionCycleTracker.binding(
                      for: .voice,
                      fallback: self.snapshot.mappings
                  ).startsRemoteSpeech,
                  self.remoteSessionPolicy.activeTaskID == nil,
                  let taskID = self.beginSpeech(sampleRate),
                  self.remoteSessionPolicy.accept(taskID: taskID) else { return false }
            return true
        }
        bluetooth.onPCM16 = { [weak self] samples, _ in
            guard let self,
                  let taskID = self.remoteSessionPolicy.activeTaskID,
                  self.remoteSessionPolicy.allowsPCM(taskID: taskID) else { return }
            self.appendPCM(samples, taskID)
        }
        bluetooth.onVoiceStop = { [weak self] in
            guard let self,
                  let taskID = self.remoteSessionPolicy.activeTaskID,
                  self.remoteSessionPolicy.finish(taskID: taskID) else { return }
            self.endSpeech(taskID)
            self.scheduleProcessingCompletionPoll()
        }
        bluetooth.onVoiceCancel = { [weak self] in
            guard let self, let taskID = self.remoteSessionPolicy.cancel() else { return }
            self.cancelSpeech(taskID)
        }
        hid.onPermissionChange = { [weak self] permission in
            self?.snapshot.inputMonitoringPermission = permission
            self?.publish()
        }
        hid.onEvent = { [weak self] event in
            self?.handleHID(event)
        }
    }

    private func handleHID(_ event: RemoteHIDButtonEvent) {
        let button: RemoteButton
        let binding: RemoteBinding
        switch event {
        case .buttonDown(let pressedButton):
            button = pressedButton
            binding = actionCycleTracker.begin(
                button: button,
                mapping: snapshot.mappings
            )
            if button == .voice, binding.startsRemoteSpeech {
                bluetooth.observeVoiceButton(isDown: true)
            }
            snapshot.pressedButton = button
            publish()
        case .buttonUp(let releasedButton):
            button = releasedButton
            binding = actionCycleTracker.end(
                button: button,
                fallback: snapshot.mappings
            )
            if button == .voice, binding.startsRemoteSpeech {
                bluetooth.observeVoiceButton(isDown: false)
            }
            if snapshot.pressedButton == button {
                snapshot.pressedButton = nil
                publish()
            }
            return
        }
        // HID only proves voice source ownership; ATVV AUDIO_STOP still owns finalization.
        if button == .power,
           binding.replacesSystemEvent,
           !powerKeyNeutralizer.isNeutralized {
            logActionResult(
                .failed(.powerNotNeutralized),
                button: button,
                binding: binding
            )
            return
        }
        let result = actionDispatcher.dispatch(binding, for: button)
        logActionResult(result, button: button, binding: binding)
    }

    @discardableResult
    private func synchronizePowerKeyNeutralization() -> Bool {
        let shouldNeutralize = snapshot.enabled &&
            snapshot.mappings.binding(for: .power).replacesSystemEvent
        let succeeded = powerKeyNeutralizer.setNeutralized(shouldNeutralize)
        if !succeeded {
            LaunchDiagnostics.mark(
                "remote_power_neutralization desired=\(shouldNeutralize) result=failed"
            )
        }
        return succeeded
    }

    private func logActionResult(
        _ result: RemoteActionResult,
        button: RemoteButton,
        binding: RemoteBinding
    ) {
        let family = binding.descriptor?.family.rawValue ?? "unknown"
        LaunchDiagnostics.mark(
            "remote_action button=\(button.rawValue) action=\(binding.actionID.rawValue) " +
                "binding_schema=\(binding.schemaVersion) executor=\(family) result=\(result.logCode)"
        )
    }

    private func scheduleProcessingCompletionPoll(attempt: Int = 0) {
        processingPollGeneration += 1
        let generation = processingPollGeneration
        pollProcessingCompletion(generation: generation, attempt: attempt)
    }

    private func pollProcessingCompletion(generation: Int, attempt: Int) {
        guard generation == processingPollGeneration else { return }
        if !speechPipelineIsBusy() {
            bluetooth.processingDidFinish()
            return
        }
        guard attempt < 240 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pollProcessingCompletion(generation: generation, attempt: attempt + 1)
        }
    }

    private func publish() {
        onSnapshot?(snapshot)
    }
}
