import Foundation

enum RemoteConnectionPhase: Equatable {
    case disabled
    case bluetoothUnavailable
    case unpaired
    case scanning
    case connecting
    case negotiating
    case ready
    case listening
    case processing
    case retrying(attempt: Int)
    case busy
    case protocolFailure(reason: String)
}

enum RemoteConnectionEvent: Equatable {
    case setEnabled(Bool)
    case bluetoothUnavailable
    case bluetoothAvailable(enabled: Bool)
    case noPeripheralFound
    case peripheralFound
    case connected
    case capabilitiesAccepted
    case voiceStarted
    case voiceStopped
    case processingFinished
    case speechBusy
    case disconnected
    case connectionFailed(reason: String)
    case retryTimerFired
    case protocolFailed(reason: String)
}

struct RemoteConnectionPolicy {
    private(set) var phase: RemoteConnectionPhase = .disabled
    private var enabled = false
    private var retryAttempt = 0
    private var resumeAfterTransient: RemoteConnectionPhase = .unpaired

    mutating func handle(_ event: RemoteConnectionEvent) {
        if case .setEnabled(false) = event {
            enabled = false
            retryAttempt = 0
            phase = .disabled
            return
        }
        guard enabled || enablesPolicy(event) else { return }

        switch event {
        case .setEnabled(true):
            enabled = true
            retryAttempt = 0
            phase = .scanning
        case .bluetoothUnavailable:
            resumeAfterTransient = phase == .disabled ? .unpaired : phase
            phase = .bluetoothUnavailable
        case .bluetoothAvailable(let shouldEnable):
            enabled = shouldEnable
            phase = shouldEnable ? .scanning : .disabled
        case .noPeripheralFound:
            phase = .unpaired
        case .peripheralFound:
            phase = .connecting
        case .connected:
            phase = .negotiating
        case .capabilitiesAccepted:
            retryAttempt = 0
            phase = .ready
        case .voiceStarted:
            phase = .listening
        case .voiceStopped:
            phase = .processing
        case .processingFinished:
            phase = resumeAfterTransient == .scanning ? .scanning : .ready
        case .speechBusy:
            resumeAfterTransient = phase
            phase = .busy
        case .disconnected, .connectionFailed:
            retryAttempt += 1
            phase = .retrying(attempt: retryAttempt)
        case .retryTimerFired:
            phase = .scanning
        case .protocolFailed(let reason):
            phase = .protocolFailure(reason: reason)
        case .setEnabled(false):
            break
        }
    }

    private mutating func enablesPolicy(_ event: RemoteConnectionEvent) -> Bool {
        switch event {
        case .setEnabled(true):
            return true
        case .bluetoothUnavailable:
            return true
        case .bluetoothAvailable(let shouldEnable):
            return shouldEnable
        default:
            return false
        }
    }
}

enum RemotePermissionStatus: String, Equatable {
    case unknown
    case allowed
    case denied
    case restricted
}

struct RemoteDeviceSnapshot: Equatable {
    var name: String?
    var model: String?
    var batteryPercent: Int?
    var signalStrength: Int?
}

struct RemoteVoicePipelineSnapshot: Equatable {
    var controlReady = false
    var audioPacketCount = 0
    var pcmLevelDB: Float = -100
    var typeWhaleSessionActive = false
}

struct RemoteBluetoothSnapshot: Equatable {
    var phase: RemoteConnectionPhase = .disabled
    var bluetoothPermission: RemotePermissionStatus = .unknown
    var device = RemoteDeviceSnapshot()
    var pipeline = RemoteVoicePipelineSnapshot()
}

struct RemoteInputSnapshot: Equatable {
    var enabled: Bool
    var phase: RemoteConnectionPhase
    var bluetoothPermission: RemotePermissionStatus
    var inputMonitoringPermission: RemotePermissionStatus
    var device: RemoteDeviceSnapshot
    var pipeline: RemoteVoicePipelineSnapshot
    var mappings: RemoteButtonMapping
    var pressedButton: RemoteButton?

    static let initial = RemoteInputSnapshot(
        enabled: false,
        phase: .disabled,
        bluetoothPermission: .unknown,
        inputMonitoringPermission: .unknown,
        device: RemoteDeviceSnapshot(),
        pipeline: RemoteVoicePipelineSnapshot(),
        mappings: .defaults,
        pressedButton: nil
    )
}
