import AVFAudio
import Foundation

enum RemotePCMBufferError: Error {
    case emptySamples
    case invalidSampleRate
    case allocationFailed
}

enum RemotePCMBufferFactory {
    static func make(samples: [Int16], sampleRate: Int) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty else { throw RemotePCMBufferError.emptySamples }
        guard sampleRate > 0 else { throw RemotePCMBufferError.invalidSampleRate }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.int16ChannelData?[0] else {
            throw RemotePCMBufferError.allocationFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return buffer
    }
}
