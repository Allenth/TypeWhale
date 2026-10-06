import Foundation

@main
struct TTSLabWaveValidatorCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-wave-validator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let validator = TTSLabWaveValidator()
        let valid = root.appendingPathComponent("valid.wav")
        try makePCM16WAV(
            samples: [0, 1_200, -1_200, 2_400, -2_400],
            output: valid
        )
        let report = try validator.validate(url: valid)
        precondition(report.frameCount == 5)
        precondition(report.peak > 0)
        precondition(!report.isSilent)

        let silent = root.appendingPathComponent("silent.wav")
        try makePCM16WAV(samples: Array(repeating: 0, count: 100), output: silent)
        do {
            _ = try validator.validate(url: silent)
            preconditionFailure("silent WAV must fail")
        } catch TTSLabWaveValidationError.silent {
        }

        let empty = root.appendingPathComponent("empty.wav")
        try Data().write(to: empty)
        do {
            _ = try validator.validate(url: empty)
            preconditionFailure("empty WAV must fail")
        } catch TTSLabWaveValidationError.invalidContainer {
        }

        print("TTSLabWaveValidatorCheck passed")
    }

    private static func makePCM16WAV(samples: [Int16], output: URL) throws {
        var data = Data()
        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        let pcmBytes = UInt32(samples.count * MemoryLayout<Int16>.size)
        appendASCII("RIFF")
        appendUInt32(36 + pcmBytes)
        appendASCII("WAVEfmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(24_000)
        appendUInt32(48_000)
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(pcmBytes)
        for sample in samples {
            appendUInt16(UInt16(bitPattern: sample))
        }
        try data.write(to: output)
    }
}
