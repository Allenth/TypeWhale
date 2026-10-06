import CoreBluetooth
import Foundation

final class RemoteBluetoothController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let atvvServiceUUID = CBUUID(string: RemoteATVVProtocol.serviceUUID)
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")
    private static let deviceInformationServiceUUID = CBUUID(string: "180A")
    private static let modelNumberUUID = CBUUID(string: "2A24")
    private static let txUUID = CBUUID(string: RemoteATVVProtocol.txUUID)
    private static let rxUUID = CBUUID(string: RemoteATVVProtocol.rxUUID)
    private static let controlUUID = CBUUID(string: RemoteATVVProtocol.controlUUID)
    private static let maximumCapabilityAttempts = 3
    private static let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 16, 32, 60]

    var onSnapshot: ((RemoteBluetoothSnapshot) -> Void)?
    var onVoiceStart: ((Int) -> Bool)?
    var onPCM16: (([Int16], Int) -> Void)?
    var onVoiceStop: (() -> Void)?
    var onVoiceCancel: (() -> Void)?

    private(set) var snapshot = RemoteBluetoothSnapshot()
    private var policy = RemoteConnectionPolicy()
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private let protocolHandler = RemoteATVVProtocol()
    private var isEnabled = false
    private var capabilityAttempt = 0
    private var capabilityWatchdog: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var remoteSessionActive = false
    private var voiceControlPolicy = RemoteVoiceControlPolicy()
    private var pendingAudioStart: (reason: UInt8, codec: RemoteATVVCodec, streamID: UInt8)?
    private var streamID: UInt8 = 0
    private var remoteSessionStartedAtUptime: UInt64?
    private var firstAudioAtUptime: UInt64?
    private var lastAudioAtUptime: UInt64?
    private var lastAudioStartReason: UInt8?
    private var lateAudioFrameCount = 0

    func start(enabled: Bool) {
        isEnabled = enabled
        updatePolicy(.setEnabled(enabled))
        guard enabled else { return }
        if central == nil {
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        } else if central?.state == .poweredOn {
            startDiscovery()
        } else {
            refreshBluetoothAvailability()
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start(enabled: true)
        } else {
            stop()
        }
    }

    func scan() {
        guard isEnabled else { return }
        reconnectWorkItem?.cancel()
        reconnectAttempt = 0
        if central == nil { start(enabled: true) }
        guard central?.state == .poweredOn else {
            refreshBluetoothAvailability()
            return
        }
        startDiscovery()
    }

    func stopScan() {
        central?.stopScan()
        if isEnabled, peripheral == nil {
            updatePolicy(.noPeripheralFound)
        }
    }

    func processingDidFinish() {
        guard isEnabled else { return }
        updatePolicy(.processingFinished)
    }

    func observeVoiceButton(isDown: Bool) {
        guard isEnabled else { return }
        let action = voiceControlPolicy.observeVoiceButton(
            isDown: isDown,
            observedAt: DispatchTime.now().uptimeNanoseconds
        )
        logVoiceControl(event: isDown ? "voice_hid_down" : "voice_hid_up", action: action)
        if action == .none, pendingAudioStart != nil {
            pendingAudioStart = nil
        }
        guard action == .beginSessionFromAudioStart,
              let pendingAudioStart else { return }
        self.pendingAudioStart = nil
        beginSessionFromAudioStart(
            reason: pendingAudioStart.reason,
            codec: pendingAudioStart.codec,
            streamID: pendingAudioStart.streamID
        )
    }

    func stop() {
        isEnabled = false
        capabilityWatchdog?.cancel()
        reconnectWorkItem?.cancel()
        central?.stopScan()
        finishRemoteSession(cancelled: true, reason: "controller_stop")
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            central?.cancelPeripheralConnection(peripheral)
        }
        clearPeripheralState()
        updatePolicy(.setEnabled(false))
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshBluetoothAvailability()
        guard isEnabled, central.state == .poweredOn else { return }
        startDiscovery()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isEnabled, self.peripheral == nil else { return }
        snapshot.device.signalStrength = RSSI.intValue
        snapshot.device.name = displayName(for: peripheral)
        publishSnapshot()
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isEnabled, peripheral === self.peripheral else { return }
        reconnectAttempt = 0
        peripheral.delegate = self
        snapshot.device.name = displayName(for: peripheral)
        updatePolicy(.connected)
        peripheral.discoverServices([
            Self.atvvServiceUUID,
            Self.batteryServiceUUID,
            Self.deviceInformationServiceUUID,
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        clearPeripheralState()
        updatePolicy(.connectionFailed(reason: "连接超时"))
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        finishRemoteSession(cancelled: true, reason: "peripheral_disconnected")
        clearPeripheralState()
        guard isEnabled else { return }
        updatePolicy(.disconnected)
        scheduleReconnect()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        if error != nil {
            failConnection(message: "无法读取遥控器服务")
            return
        }
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case Self.atvvServiceUUID:
                peripheral.discoverCharacteristics([
                    Self.txUUID,
                    Self.rxUUID,
                    Self.controlUUID,
                ], for: service)
            case Self.batteryServiceUUID:
                peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: service)
            case Self.deviceInformationServiceUUID:
                peripheral.discoverCharacteristics([Self.modelNumberUUID], for: service)
            default:
                break
            }
        }
        if peripheral.services?.contains(where: { $0.uuid == Self.atvvServiceUUID }) != true {
            failProtocol(message: "设备不支持遥控器语音服务")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if error != nil {
            failConnection(message: "无法读取遥控器功能")
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.txUUID:
                txCharacteristic = characteristic
            case Self.rxUUID:
                rxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.controlUUID:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.batteryLevelUUID:
                peripheral.readValue(for: characteristic)
            case Self.modelNumberUUID:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
        maybeBeginCapabilityNegotiation()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if error != nil {
            failConnection(message: "无法订阅遥控器语音")
            return
        }
        maybeBeginCapabilityNegotiation()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.controlUUID:
            handleControl(protocolHandler.parseControl(data))
        case Self.rxUUID:
            handleAudio(data)
        case Self.batteryLevelUUID:
            if let level = data.first {
                snapshot.device.batteryPercent = min(100, Int(level))
                publishSnapshot()
            }
        case Self.modelNumberUUID:
            let model = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            if let model, !model.isEmpty {
                snapshot.device.model = String(model.prefix(80))
                publishSnapshot()
            }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, error != nil else { return }
        failConnection(message: "遥控器控制指令发送失败")
    }

    private func refreshBluetoothAvailability() {
        snapshot.bluetoothPermission = bluetoothPermission
        guard let central else {
            publishSnapshot()
            return
        }
        switch central.state {
        case .poweredOn:
            if isEnabled, snapshot.phase == .bluetoothUnavailable {
                updatePolicy(.bluetoothAvailable(enabled: true))
            } else {
                publishSnapshot()
            }
        case .unknown, .resetting:
            publishSnapshot()
        case .unsupported, .unauthorized, .poweredOff:
            updatePolicy(.bluetoothUnavailable)
        @unknown default:
            updatePolicy(.bluetoothUnavailable)
        }
    }

    private var bluetoothPermission: RemotePermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    private func startDiscovery() {
        guard isEnabled, let central, central.state == .poweredOn else { return }
        central.stopScan()
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.atvvServiceUUID])
        if let existing = connected.first {
            connect(existing)
            return
        }
        clearPeripheralState()
        updatePolicy(.bluetoothAvailable(enabled: true))
        central.scanForPeripherals(
            withServices: [Self.atvvServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        updatePolicy(.peripheralFound)
        central?.connect(peripheral, options: nil)
    }

    private func maybeBeginCapabilityNegotiation() {
        guard let peripheral,
              let txCharacteristic,
              rxCharacteristic?.isNotifying == true,
              controlCharacteristic?.isNotifying == true,
              capabilityAttempt == 0 else { return }
        updatePolicy(.connected)
        capabilityAttempt = 1
        write(protocolHandler.getCapabilitiesCommand, to: txCharacteristic, on: peripheral)
        armCapabilityWatchdog()
    }

    private func armCapabilityWatchdog() {
        capabilityWatchdog?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled, self.snapshot.phase == .negotiating else { return }
            guard self.capabilityAttempt < Self.maximumCapabilityAttempts,
                  let peripheral = self.peripheral,
                  let txCharacteristic = self.txCharacteristic else {
                self.failProtocol(message: "遥控器语音协商超时")
                return
            }
            self.capabilityAttempt += 1
            self.write(self.protocolHandler.getCapabilitiesCommand, to: txCharacteristic, on: peripheral)
            self.armCapabilityWatchdog()
        }
        capabilityWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func handleControl(_ event: RemoteATVVControlEvent) {
        switch event {
        case .capabilities(let capabilities):
            do {
                try protocolHandler.acceptCapabilities(capabilities)
                pendingAudioStart = nil
                voiceControlPolicy.configure(
                    usesExplicitAudioStop: capabilities.version == .v10
                )
                capabilityWatchdog?.cancel()
                capabilityAttempt = 0
                snapshot.pipeline.controlReady = true
                LaunchDiagnostics.mark(
                    "remote_voice_capabilities version=\(capabilities.version.logName) codecs=\(capabilities.codecs) interaction_model=\(capabilities.interactionModel) frame_size=\(capabilities.frameSize) explicit_audio_stop=\(capabilities.version == .v10)"
                )
                updatePolicy(.capabilitiesAccepted)
            } catch {
                failProtocol(message: error.localizedDescription)
            }
        case .startSearch:
            pendingAudioStart = nil
            let action = voiceControlPolicy.handle(.startSearch)
            logVoiceControl(event: "start_search", action: action)
            switch action {
            case .beginSessionAndOpenMicrophone:
                guard let codec = protocolHandler.codec else {
                    voiceControlPolicy.reset()
                    return
                }
                guard beginRemoteSession(sampleRate: codec.sampleRate) else {
                    voiceControlPolicy.reset()
                    return
                }
                do {
                    write(try protocolHandler.micOpenCommand())
                } catch {
                    finishRemoteSession(cancelled: true, reason: "mic_open_command_failed")
                    failProtocol(message: error.localizedDescription)
                }
            case .closeMicrophoneAndFinishSession:
                closeMicrophoneIfPossible()
                finishRemoteSession(cancelled: false, reason: "legacy_toggle_start_search")
            case .beginSessionFromAudioStart,
                 .awaitCorrelatedVoiceButton,
                 .ignoreDuplicateStartSearch,
                 .ignoreUnexpectedAudioStart,
                 .finishSession,
                 .none:
                break
            }
        case .audioStart(let reason, let codec, let newStreamID):
            let action = voiceControlPolicy.handle(
                .audioStart,
                observedAt: DispatchTime.now().uptimeNanoseconds
            )
            logVoiceControl(
                event: "audio_start reason=\(reason) codec=\(codec.rawValue) stream_id=\(newStreamID)",
                action: action
            )
            switch action {
            case .awaitCorrelatedVoiceButton:
                pendingAudioStart = (reason, codec, newStreamID)
            case .beginSessionFromAudioStart:
                pendingAudioStart = nil
                beginSessionFromAudioStart(reason: reason, codec: codec, streamID: newStreamID)
            case .ignoreUnexpectedAudioStart:
                pendingAudioStart = nil
            default:
                pendingAudioStart = nil
                streamID = newStreamID
                lastAudioStartReason = reason
            }
        case .audioStop(let reason):
            pendingAudioStart = nil
            let action = voiceControlPolicy.handle(.audioStop)
            logVoiceControl(event: "audio_stop reason=\(reason)", action: action)
            if action == .finishSession {
                finishRemoteSession(cancelled: false, reason: "audio_stop_\(reason)")
            }
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            protocolHandler.applyAudioSync(
                codec: codec,
                sequence: sequence,
                predictor: predictor,
                stepIndex: stepIndex
            )
        case .micOpenError:
            finishRemoteSession(cancelled: true, reason: "mic_open_rejected")
            failProtocol(message: "遥控器拒绝开启语音")
        case .unknown:
            break
        }
    }

    private func beginRemoteSession(sampleRate: Int) -> Bool {
        guard !remoteSessionActive else { return true }
        guard onVoiceStart?(sampleRate) == true else {
            updatePolicy(.speechBusy)
            closeMicrophoneIfPossible()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.isEnabled, self.snapshot.phase == .busy else { return }
                self.updatePolicy(.processingFinished)
            }
            return false
        }
        remoteSessionActive = true
        snapshot.pipeline.audioPacketCount = 0
        snapshot.pipeline.pcmLevelDB = -100
        snapshot.pipeline.typeWhaleSessionActive = true
        let now = DispatchTime.now().uptimeNanoseconds
        remoteSessionStartedAtUptime = now
        firstAudioAtUptime = nil
        lastAudioAtUptime = nil
        lastAudioStartReason = nil
        lateAudioFrameCount = 0
        LaunchDiagnostics.mark(
            "remote_voice_session phase=begin sample_rate=\(sampleRate) control_phase=\(voiceControlPolicy.phase.rawValue)"
        )
        updatePolicy(.voiceStarted)
        return true
    }

    private func beginSessionFromAudioStart(
        reason: UInt8,
        codec: RemoteATVVCodec,
        streamID: UInt8
    ) {
        self.streamID = streamID
        guard beginRemoteSession(sampleRate: codec.sampleRate) else {
            voiceControlPolicy.reset()
            return
        }
        lastAudioStartReason = reason
        LaunchDiagnostics.mark(
            "remote_voice_session source=correlated_hid_audio_start stream_id=\(streamID)"
        )
    }

    private func handleAudio(_ data: Data) {
        guard remoteSessionActive else {
            lateAudioFrameCount += 1
            if lateAudioFrameCount <= 3 || lateAudioFrameCount % 25 == 0 {
                LaunchDiagnostics.mark(
                    "remote_voice_audio phase=dropped_inactive count=\(lateAudioFrameCount) bytes=\(data.count) control_phase=\(voiceControlPolicy.phase.rawValue)"
                )
            }
            return
        }
        guard let frame = protocolHandler.decodeAudio(data),
              let codec = protocolHandler.codec else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if firstAudioAtUptime == nil { firstAudioAtUptime = now }
        lastAudioAtUptime = now
        snapshot.pipeline.audioPacketCount += 1
        snapshot.pipeline.pcmLevelDB = levelDB(samples: frame.samples)
        publishSnapshot()
        onPCM16?(frame.samples, codec.sampleRate)
    }

    private func finishRemoteSession(cancelled: Bool, reason: String) {
        voiceControlPolicy.reset()
        pendingAudioStart = nil
        guard remoteSessionActive else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let sessionDuration = elapsedMilliseconds(from: remoteSessionStartedAtUptime, to: now)
        let firstAudioDelay = elapsedMilliseconds(from: remoteSessionStartedAtUptime, to: firstAudioAtUptime)
        let controlAfterLastAudio = elapsedMilliseconds(from: lastAudioAtUptime, to: now)
        let sessionDurationText = sessionDuration.map(String.init) ?? "unknown"
        let firstAudioDelayText = firstAudioDelay.map(String.init) ?? "none"
        let controlAfterLastAudioText = controlAfterLastAudio.map(String.init) ?? "none"
        let audioStartReasonText = lastAudioStartReason.map(String.init) ?? "unknown"
        LaunchDiagnostics.mark(
            "remote_voice_session phase=finish cancelled=\(cancelled) reason=\(reason) frames=\(snapshot.pipeline.audioPacketCount) duration_ms=\(sessionDurationText) first_audio_delay_ms=\(firstAudioDelayText) control_after_last_audio_ms=\(controlAfterLastAudioText) audio_start_reason=\(audioStartReasonText)"
        )
        remoteSessionActive = false
        snapshot.pipeline.typeWhaleSessionActive = false
        remoteSessionStartedAtUptime = nil
        firstAudioAtUptime = nil
        lastAudioAtUptime = nil
        lastAudioStartReason = nil
        if cancelled {
            onVoiceCancel?()
            if isEnabled { updatePolicy(.disconnected) }
        } else {
            updatePolicy(.voiceStopped)
            onVoiceStop?()
        }
    }

    private func closeMicrophoneIfPossible() {
        guard let command = try? protocolHandler.micCloseCommand(streamID: streamID) else { return }
        write(command)
    }

    private func write(_ data: Data) {
        guard let peripheral, let txCharacteristic else { return }
        write(data, to: txCharacteristic, on: peripheral)
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func failConnection(message: String) {
        updatePolicy(.connectionFailed(reason: message))
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    private func failProtocol(message: String) {
        capabilityWatchdog?.cancel()
        updatePolicy(.protocolFailed(reason: message))
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        guard isEnabled else { return }
        let index = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[index]
        reconnectAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.updatePolicy(.retryTimerFired)
            self.startDiscovery()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func clearPeripheralState() {
        capabilityWatchdog?.cancel()
        capabilityWatchdog = nil
        capabilityAttempt = 0
        pendingAudioStart = nil
        voiceControlPolicy.reset()
        peripheral?.delegate = nil
        peripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        controlCharacteristic = nil
        snapshot.device = RemoteDeviceSnapshot()
        snapshot.pipeline = RemoteVoicePipelineSnapshot()
        publishSnapshot()
    }

    private func updatePolicy(_ event: RemoteConnectionEvent) {
        policy.handle(event)
        snapshot.phase = policy.phase
        publishSnapshot()
    }

    private func publishSnapshot() {
        onSnapshot?(snapshot)
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        let trimmed = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "小米蓝牙遥控器 2 Pro" : String(trimmed.prefix(80))
    }

    private func levelDB(samples: [Int16]) -> Float {
        guard let peak = samples.map({ abs(Int32($0)) }).max(), peak > 0 else { return -100 }
        return max(-100, 20 * log10(Float(peak) / Float(Int16.max)))
    }

    private func logVoiceControl(event: String, action: RemoteVoiceControlPolicy.Action) {
        LaunchDiagnostics.mark(
            "remote_voice_control event=\(event) action=\(action.rawValue) control_phase=\(voiceControlPolicy.phase.rawValue) session_active=\(remoteSessionActive) frames=\(snapshot.pipeline.audioPacketCount) uptime_ns=\(DispatchTime.now().uptimeNanoseconds)"
        )
    }

    private func elapsedMilliseconds(from start: UInt64?, to end: UInt64?) -> UInt64? {
        guard let start, let end, end >= start else { return nil }
        return (end - start) / 1_000_000
    }
}

private extension RemoteATVVVersion {
    var logName: String {
        switch self {
        case .v04: return "0.4"
        case .v10: return "1.0"
        }
    }
}
