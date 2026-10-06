import AVFAudio
import Foundation

@main
struct AudioRecorderExternalPCMCheck {
    static func main() throws {
        let input: [Int16] = [Int16.min, -16_384, 0, 16_384, Int16.max]
        let buffer = try RemotePCMBufferFactory.make(samples: input, sampleRate: 16_000)
        precondition(buffer.format.sampleRate == 16_000)
        precondition(buffer.format.channelCount == 1)
        precondition(buffer.frameLength == input.count)
        guard let channel = buffer.int16ChannelData?[0] else {
            preconditionFailure("expected planar Int16 channel")
        }
        precondition(Array(UnsafeBufferPointer(start: channel, count: input.count)) == input)

        do {
            _ = try RemotePCMBufferFactory.make(samples: [], sampleRate: 16_000)
            preconditionFailure("empty samples must be rejected")
        } catch RemotePCMBufferError.emptySamples {}

        do {
            _ = try RemotePCMBufferFactory.make(samples: [0], sampleRate: 0)
            preconditionFailure("invalid sample rates must be rejected")
        } catch RemotePCMBufferError.invalidSampleRate {}
        print("AudioRecorderExternalPCMCheck passed")
    }
}
