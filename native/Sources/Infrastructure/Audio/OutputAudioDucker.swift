import CoreAudio
import Foundation

final class OutputAudioDucker {
    struct VolumeControl: Hashable {
        let deviceID: AudioDeviceID
        let element: AudioObjectPropertyElement
    }

    private final class VolumeSnapshot {
        let control: VolumeControl
        let originalVolume: Float32
        let duckedVolume: Float32
        var lastAppliedVolume: Float32

        init(control: VolumeControl, originalVolume: Float32, duckedVolume: Float32) {
            self.control = control
            self.originalVolume = originalVolume
            self.duckedVolume = duckedVolume
            lastAppliedVolume = duckedVolume
        }
    }

    private static let duckedVolume: Float32 = 0.0
    private static let restoreTolerance: Float32 = 0.03
    private static let restoreDelay: TimeInterval = 1.0
    private static let restoreRampDuration: TimeInterval = 0.5
    private static let restoreRampSteps = 8
    private let controls: () -> [VolumeControl]
    private let readVolume: (VolumeControl) -> Float32?
    private let writeVolume: (Float32, VolumeControl) -> Void
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var snapshots: [VolumeSnapshot] = []
    private var restoreWorkItems: [DispatchWorkItem] = []
    private var restoreGeneration: UInt = 0

    convenience init() {
        self.init(
            controls: {
                guard let deviceID = OutputAudioDucker.defaultOutputDeviceID() else { return [] }
                return OutputAudioDucker.writableVolumeControls(for: deviceID).map {
                    VolumeControl(deviceID: deviceID, element: $0)
                }
            },
            readVolume: { control in
                OutputAudioDucker.volume(deviceID: control.deviceID, element: control.element)
            },
            writeVolume: { volume, control in
                OutputAudioDucker.setVolume(volume, deviceID: control.deviceID, element: control.element)
            },
            schedule: { delay, workItem in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        )
    }

    init(
        controls: @escaping () -> [VolumeControl],
        readVolume: @escaping (VolumeControl) -> Float32?,
        writeVolume: @escaping (Float32, VolumeControl) -> Void,
        schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void
    ) {
        self.controls = controls
        self.readVolume = readVolume
        self.writeVolume = writeVolume
        self.schedule = schedule
    }

    var isDucking: Bool {
        !snapshots.isEmpty
    }

    func duckIfNeeded(enabled: Bool) {
        guard enabled else { return }
        cancelPendingRestore()
        let availableControls = controls()
        guard !availableControls.isEmpty || !snapshots.isEmpty else { return }

        var captured: [VolumeSnapshot] = []
        var retainedControls = Set<VolumeControl>()
        for snapshot in snapshots {
            guard let currentVolume = readVolume(snapshot.control),
                  abs(currentVolume - snapshot.lastAppliedVolume) <= Self.restoreTolerance else {
                continue
            }
            writeVolume(snapshot.duckedVolume, snapshot.control)
            snapshot.lastAppliedVolume = snapshot.duckedVolume
            captured.append(snapshot)
            retainedControls.insert(snapshot.control)
        }

        for control in availableControls where !retainedControls.contains(control) {
            guard let volume = readVolume(control) else { continue }
            let duckedVolume = min(volume, Self.duckedVolume)
            writeVolume(duckedVolume, control)
            captured.append(VolumeSnapshot(
                control: control,
                originalVolume: volume,
                duckedVolume: duckedVolume
            ))
        }
        snapshots = captured
    }

    func restore() {
        cancelPendingRestore()
        guard !snapshots.isEmpty else { return }
        let generation = restoreGeneration

        let startWorkItem = DispatchWorkItem { [weak self] in
            self?.startRampRestore(generation: generation)
        }
        restoreWorkItems.append(startWorkItem)
        schedule(Self.restoreDelay, startWorkItem)
    }

    private func startRampRestore(generation: UInt) {
        guard generation == restoreGeneration else { return }
        restoreWorkItems.removeAll { $0.isCancelled }
        for snapshot in snapshots {
            guard let currentVolume = readVolume(snapshot.control),
                  abs(currentVolume - snapshot.lastAppliedVolume) <= Self.restoreTolerance else {
                release(snapshot)
                continue
            }
            scheduleRampRestore(snapshot: snapshot, from: currentVolume, generation: generation)
        }
    }

    private func scheduleRampRestore(snapshot: VolumeSnapshot, from startVolume: Float32, generation: UInt) {
        guard Self.restoreRampSteps > 0 else {
            writeVolume(snapshot.originalVolume, snapshot.control)
            release(snapshot)
            return
        }
        for step in 1...Self.restoreRampSteps {
            let progress = Float32(step) / Float32(Self.restoreRampSteps)
            let targetVolume = startVolume + (snapshot.originalVolume - startVolume) * progress
            let delay = Self.restoreRampDuration * TimeInterval(step) / TimeInterval(Self.restoreRampSteps)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      generation == self.restoreGeneration,
                      self.owns(snapshot),
                      let currentVolume = self.readVolume(snapshot.control),
                      abs(currentVolume - snapshot.lastAppliedVolume) <= Self.restoreTolerance else {
                    if let self, generation == self.restoreGeneration, self.owns(snapshot) {
                        self.release(snapshot)
                    }
                    return
                }
                self.writeVolume(targetVolume, snapshot.control)
                snapshot.lastAppliedVolume = targetVolume
                if step == Self.restoreRampSteps {
                    self.release(snapshot)
                }
            }
            restoreWorkItems.append(workItem)
            schedule(delay, workItem)
        }
    }

    private func cancelPendingRestore() {
        restoreGeneration &+= 1
        restoreWorkItems.forEach { $0.cancel() }
        restoreWorkItems.removeAll()
    }

    private func owns(_ snapshot: VolumeSnapshot) -> Bool {
        snapshots.contains { $0 === snapshot }
    }

    private func release(_ snapshot: VolumeSnapshot) {
        snapshots.removeAll { $0 === snapshot }
        if snapshots.isEmpty {
            restoreWorkItems.removeAll()
        }
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
