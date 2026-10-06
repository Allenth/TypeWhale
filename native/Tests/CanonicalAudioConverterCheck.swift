import AVFAudio

@main
struct CanonicalAudioConverterCheck {
    static func main() throws {
        for (rate, channels) in [
            (44_100.0, AVAudioChannelCount(1)),
            (48_000.0, AVAudioChannelCount(2)),
        ] {
            let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: channels,
                interleaved: false
            )!
            let input = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(rate / 10)
            )!
            input.frameLength = input.frameCapacity
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(input.frameLength) {
                    input.floatChannelData![channel][frame] = 0.25
                }
            }

            let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
            let output = try converter.convert(input)
            precondition(output.format == CanonicalAudioConverter.format)
            precondition(output.frameLength > 0)
            precondition(output.floatChannelData![0][0] != 0)
        }

        print("CanonicalAudioConverterCheck passed")
    }
}
