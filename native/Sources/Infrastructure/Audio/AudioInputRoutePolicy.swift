import CoreAudio

enum AudioInputSelectionResolution: Equatable {
    case systemDefault(AudioInputDevice)
    case preferredBuiltIn(AudioInputDevice, originalDefault: AudioInputDevice)
    case manual(AudioInputDevice)
    case downgradeToSystemDefault(AudioInputDevice)
    case unavailable
}

struct AudioInputSwitchIntent: Equatable {
    let generation: UInt64
    let targetUID: String
}

struct AudioInputSwitchGeneration {
    private(set) var latest: UInt64 = 0

    mutating func issue(targetUID: String) -> AudioInputSwitchIntent {
        latest &+= 1
        return AudioInputSwitchIntent(generation: latest, targetUID: targetUID)
    }

    func accepts(_ intent: AudioInputSwitchIntent) -> Bool {
        intent.generation == latest
    }
}

enum AudioInputRoutePolicy {
    static func resolve(
        selectedUID: String,
        devices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID?,
        preferBuiltInMicForBluetoothSystemDefault: Bool = false
    ) -> AudioInputSelectionResolution {
        let systemDefault = defaultDeviceID.flatMap { id in
            devices.first { $0.id == id }
        }

        guard !selectedUID.isEmpty else {
            if preferBuiltInMicForBluetoothSystemDefault,
               let originalDefault = systemDefault,
               originalDefault.isLikelyBluetoothHeadsetMicrophone,
               let builtIn = devices.first(where: { $0.isLikelyBuiltInMicrophone }) {
                return .preferredBuiltIn(builtIn, originalDefault: originalDefault)
            }
            return systemDefault.map(AudioInputSelectionResolution.systemDefault) ?? .unavailable
        }
        if let selected = devices.first(where: { $0.uid == selectedUID }) {
            return .manual(selected)
        }
        return systemDefault.map(AudioInputSelectionResolution.downgradeToSystemDefault) ?? .unavailable
    }
}

extension AudioInputDevice {
    var isLikelyBuiltInMicrophone: Bool {
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return true
        }
        let normalized = name.lowercased()
        return normalized.contains("macbook")
            || normalized.contains("built-in")
            || normalized.contains("built in")
            || normalized.contains("内建")
            || normalized.contains("内置")
    }

    var isLikelyBluetoothHeadsetMicrophone: Bool {
        if transportType == kAudioDeviceTransportTypeBluetooth {
            return true
        }
        let normalized = name.lowercased()
        return normalized.contains("airpods")
            || normalized.contains("bluetooth")
            || normalized.contains("beats")
            || normalized.contains("bose")
            || normalized.contains("sony")
            || normalized.contains("耳机")
            || normalized.contains("headset")
            || normalized.contains("headphone")
    }
}
