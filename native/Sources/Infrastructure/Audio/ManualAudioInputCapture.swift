import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

/// Captures one explicit CoreAudio device without changing the system default route.
final class ManualAudioInputCapture: @unchecked Sendable {
    private var unit: AudioUnit?
    private var callbackCount: Int32 = 0
    private var lastRenderStatus: OSStatus = noErr
    private(set) var format: AVAudioFormat
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    init(deviceID: AudioDeviceID) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw Self.error(-1, "找不到 macOS 硬件音频采集组件")
        }
        var created: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &created), "无法创建硬件麦克风采集器")
        guard let created else { throw Self.error(-1, "无法创建硬件麦克风采集器") }
        unit = created
        do {
            var enabled: UInt32 = 1
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4), "无法启用麦克风输入")
            var disabled: UInt32 = 0
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4), "无法关闭无用输出")
            var selected = deviceID
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selected, 4), "无法绑定指定麦克风")

            var hardware = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size), "无法读取麦克风格式")
            let sampleRate = hardware.mSampleRate > 0 ? hardware.mSampleRate : 48_000
            // Built-in MacBook microphone can expose 3 hardware channels, while AVAudioFormat's
            // common PCM constructors only support standard mono/stereo layouts. Ask AUHAL for a
            // mono Float32 client stream and let CoreAudio perform the device-side channel mix.
            guard let clientFormat = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(1)
            ) else {
                throw Self.error(-1, "麦克风格式不可用")
            }
            format = clientFormat
            var clientASBD = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientASBD, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "无法设置麦克风采集格式")

            var callback = AURenderCallbackStruct(
                inputProc: { refCon, flags, time, bus, frames, _ in
                    let capture = Unmanaged<ManualAudioInputCapture>.fromOpaque(refCon).takeUnretainedValue()
                    return capture.render(flags: flags, time: time, bus: bus, frames: frames)
                },
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "无法安装麦克风回调")
            try Self.check(AudioUnitInitialize(created), "无法初始化指定麦克风")
        } catch {
            AudioComponentInstanceDispose(created)
            unit = nil
            throw error
        }
    }

    func start() throws { guard let unit else { throw Self.error(-1, "麦克风采集器不可用") }; try Self.check(AudioOutputUnitStart(unit), "无法启动指定麦克风") }
    func stop() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        LaunchDiagnostics.mark("manual_audio_capture_stop callbacks=\(callbackCount) last_render_status=\(lastRenderStatus)")
    }
    deinit { stop() }

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, time: UnsafePointer<AudioTimeStamp>, bus: UInt32, frames: UInt32) -> OSStatus {
        callbackCount &+= 1
        guard let unit, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return -1 }
        buffer.frameLength = frames
        let status = AudioUnitRender(unit, flags, time, bus, frames, buffer.mutableAudioBufferList)
        lastRenderStatus = status
        guard status == noErr else { return status }
        onBuffer?(buffer)
        return noErr
    }

    private static func check(_ status: OSStatus, _ message: String) throws { if status != noErr { throw error(status, message) } }
    private static func error(_ status: OSStatus, _ message: String) -> NSError { NSError(domain: "TypeWhale.ManualAudioInputCapture", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(message)（CoreAudio \(status)）。"]) }
}
