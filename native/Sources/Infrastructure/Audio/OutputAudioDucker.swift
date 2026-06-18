import CoreAudio
import Foundation

final class OutputAudioDucker {
    private struct VolumeSnapshot {
        let deviceID: AudioDeviceID
        let element: AudioObjectPropertyElement
        let originalVolume: Float32
        let duckedVolume: Float32
    }

    private static let duckedVolume: Float32 = 0.05
    private static let restoreTolerance: Float32 = 0.03
    private static let restoreDelay: TimeInterval = 1.0
    private static let restoreRampDuration: TimeInterval = 0.5
    private static let restoreRampSteps = 8
    private var snapshots: [VolumeSnapshot] = []
    private var restoreWorkItems: [DispatchWorkItem] = []

    var isDucking: Bool {
        !snapshots.isEmpty
    }

    func duckIfNeeded(enabled: Bool) {
        cancelPendingRestore()
        guard enabled, snapshots.isEmpty, let deviceID = Self.defaultOutputDeviceID() else { return }
        let controls = Self.writableVolumeControls(for: deviceID)
        guard !controls.isEmpty else { return }

        var captured: [VolumeSnapshot] = []
        for element in controls {
            guard let volume = Self.volume(deviceID: deviceID, element: element) else { continue }
            let duckedVolume = min(volume, Self.duckedVolume)
            Self.setVolume(duckedVolume, deviceID: deviceID, element: element)
            captured.append(VolumeSnapshot(
                deviceID: deviceID,
                element: element,
                originalVolume: volume,
                duckedVolume: duckedVolume
            ))
        }
        snapshots = captured
    }

    func restore() {
        let captured = snapshots
        snapshots = []
        cancelPendingRestore()
        guard !captured.isEmpty else { return }

        let startWorkItem = DispatchWorkItem { [weak self] in
            self?.startRampRestore(captured)
        }
        restoreWorkItems.append(startWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay, execute: startWorkItem)
    }

    private func startRampRestore(_ captured: [VolumeSnapshot]) {
        restoreWorkItems.removeAll { $0.isCancelled }
        for snapshot in captured {
            guard let currentVolume = Self.volume(deviceID: snapshot.deviceID, element: snapshot.element),
                  abs(currentVolume - snapshot.duckedVolume) <= Self.restoreTolerance else {
                continue
            }
            scheduleRampRestore(snapshot: snapshot, from: currentVolume)
        }
    }

    private func scheduleRampRestore(snapshot: VolumeSnapshot, from startVolume: Float32) {
        guard Self.restoreRampSteps > 0 else {
            Self.setVolume(snapshot.originalVolume, deviceID: snapshot.deviceID, element: snapshot.element)
            return
        }
        for step in 1...Self.restoreRampSteps {
            let progress = Float32(step) / Float32(Self.restoreRampSteps)
            let targetVolume = startVolume + (snapshot.originalVolume - startVolume) * progress
            let delay = Self.restoreRampDuration * TimeInterval(step) / TimeInterval(Self.restoreRampSteps)
            let workItem = DispatchWorkItem { [weak self] in
                guard self != nil,
                      let currentVolume = Self.volume(deviceID: snapshot.deviceID, element: snapshot.element),
                      abs(currentVolume - startVolume) <= Self.restoreTolerance || step > 1 else {
                    return
                }
                if step > 1, let currentVolume = Self.volume(deviceID: snapshot.deviceID, element: snapshot.element) {
                    let previousProgress = Float32(step - 1) / Float32(Self.restoreRampSteps)
                    let expectedPrevious = startVolume + (snapshot.originalVolume - startVolume) * previousProgress
                    guard abs(currentVolume - expectedPrevious) <= Self.restoreTolerance else { return }
                }
                Self.setVolume(targetVolume, deviceID: snapshot.deviceID, element: snapshot.element)
            }
            restoreWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelPendingRestore() {
        restoreWorkItems.forEach { $0.cancel() }
        restoreWorkItems.removeAll()
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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

    private static func writableVolumeControls(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        let masterElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        if isVolumeSettable(deviceID: deviceID, element: masterElement) {
            return [masterElement]
        }

        let channels = max(outputChannelCount(for: deviceID), 2)
        return (1...channels)
            .map { AudioObjectPropertyElement($0) }
            .filter { isVolumeSettable(deviceID: deviceID, element: $0) }
    }

    private static func volume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32? {
        var address = volumeAddress(element: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setVolume(_ value: Float32, deviceID: AudioDeviceID, element: AudioObjectPropertyElement) {
        var address = volumeAddress(element: element)
        var clamped = max(0, min(1, value))
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
    }

    private static func isVolumeSettable(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
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
}
