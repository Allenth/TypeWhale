import AVFAudio
import Foundation

final class CanonicalAudioConverter {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.format) else {
            throw NSError(
                domain: "TypeWhale.CanonicalAudioConverter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建麦克风音频格式转换器。"]
            )
        }
        self.converter = converter
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = Self.format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else {
            throw conversionError("无法分配麦克风转换缓冲区。", code: 2)
        }

        var didProvideInput = false
        var converterError: NSError?
        let status = converter.convert(to: output, error: &converterError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return input
        }

        if let converterError {
            throw converterError
        }
        guard status == .haveData || status == .inputRanDry, output.frameLength > 0 else {
            throw conversionError("麦克风音频格式转换没有产生有效数据。", code: 3)
        }
        return output
    }

    private func conversionError(_ message: String, code: Int) -> NSError {
        NSError(
            domain: "TypeWhale.CanonicalAudioConverter",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
