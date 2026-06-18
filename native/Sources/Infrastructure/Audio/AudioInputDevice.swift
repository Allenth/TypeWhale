import CoreAudio
import Foundation

struct AudioInputDevice: Equatable {
    static let systemDefaultUID = ""
    static let selectionStorageKey = "audioInputDeviceUID"

    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool

    static var selectedUID: String {
        UserDefaults.standard.string(forKey: selectionStorageKey) ?? systemDefaultUID
    }

    static func saveSelectedUID(_ uid: String) {
        UserDefaults.standard.set(uid, forKey: selectionStorageKey)
    }
}

enum AudioInputDeviceProvider {
    static func devices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        return allAudioDeviceIDs().compactMap { id in
            guard inputChannelCount(for: id) > 0 else { return nil }
            let name = stringProperty(
                deviceID: id,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? "输入设备 \(id)"
            let uid = stringProperty(
                deviceID: id,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? "\(id)"
            return AudioInputDevice(
                id: id,
                uid: uid,
                name: name,
                isDefault: id == defaultID
            )
        }
        .sorted { first, second in
            if first.isDefault != second.isDefault { return first.isDefault }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    static func selectedDeviceID() -> AudioDeviceID? {
        let selectedUID = AudioInputDevice.selectedUID
        guard !selectedUID.isEmpty else { return nil }
        return devices().first { $0.uid == selectedUID }?.id
    }

    static func defaultInputDeviceName() -> String? {
        guard let id = defaultInputDeviceID() else { return nil }
        return stringProperty(
            deviceID: id,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return 0
        }
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferListPointer = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return 0
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
