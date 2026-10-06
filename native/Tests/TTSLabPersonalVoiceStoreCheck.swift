import Foundation

@main
enum TTSLabPersonalVoiceStoreCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TTSLabPersonalVoiceStoreCheck-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("valid.wav")
        try writeWave(source, sampleRate: 16_000, seconds: 1.5, amplitude: 0.12)
        let store = TTSLabPersonalVoiceStore(
            referencesRoot: root.appendingPathComponent("references", isDirectory: true)
        )
        let sourceMetrics = try store.validateRecording(at: source)
        precondition(sourceMetrics.duration > 1.4)
        let candidate = try store.prepareCandidate(from: source)
        precondition(candidate.metrics.duration >= 1.0)
        let converted = try readPCM16(candidate.referenceURL)
        let convertedRMS = sqrt(
            converted.reduce(0.0) { $0 + Double($1) * Double($1) }
                / Double(converted.count)
        ) / Double(Int16.max)
        let zeroCrossingRatio = Double(
            zip(converted, converted.dropFirst()).filter {
                ($0.0 < 0) != ($0.1 < 0)
            }.count
        ) / Double(converted.count - 1)
        precondition(
            abs(convertedRMS - (0.12 / sqrt(2.0))) < 0.01,
            "conversion changed sine RMS: \(convertedRMS)"
        )
        precondition(
            zeroCrossingRatio < 0.03,
            "conversion introduced broadband noise: \(zeroCrossingRatio)"
        )
        try store.install(candidate)
        precondition(store.discoverVoice()?.id == TTSLabPersonalVoiceStore.voiceID)

        let quiet = root.appendingPathComponent("quiet.wav")
        try writeWave(quiet, sampleRate: 16_000, seconds: 1.5, amplitude: 0.001)
        do {
            _ = try store.validateRecording(at: quiet)
            preconditionFailure("quiet recording must fail")
        } catch TTSLabPersonalVoiceValidationError.tooQuiet {}

        let manifest = root.appendingPathComponent(
            "references/\(TTSLabPersonalVoiceStore.voiceID)/reference.json"
        )
        try Data("{}".utf8).write(to: manifest)
        precondition(store.discoverVoice() == nil)
        print("TTSLabPersonalVoiceStoreCheck passed")
    }

    private static func writeWave(
        _ url: URL,
        sampleRate: Int,
        seconds: Double,
        amplitude: Double
    ) throws {
        let frames = Int(Double(sampleRate) * seconds)
        var pcm = Data(capacity: frames * 2)
        for index in 0..<frames {
            let sample = sin(2 * Double.pi * 220 * Double(index) / Double(sampleRate))
            var value = Int16(sample * amplitude * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        appendUInt32(UInt32(36 + pcm.count), to: &data)
        data.append("WAVEfmt ".data(using: .ascii)!)
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(1, to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(sampleRate * 2), to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(16, to: &data)
        data.append("data".data(using: .ascii)!)
        appendUInt32(UInt32(pcm.count), to: &data)
        data.append(pcm)
        try data.write(to: url)
    }

    private static func readPCM16(_ url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)
        guard let dataMarker = data.range(of: Data("data".utf8)) else {
            preconditionFailure("missing WAV data chunk")
        }
        let sizeOffset = dataMarker.upperBound
        let size = Int(
            UInt32(data[sizeOffset])
                | (UInt32(data[sizeOffset + 1]) << 8)
                | (UInt32(data[sizeOffset + 2]) << 16)
                | (UInt32(data[sizeOffset + 3]) << 24)
        )
        let start = sizeOffset + 4
        return stride(from: start, to: start + size, by: 2).map {
            Int16(bitPattern: UInt16(data[$0]) | (UInt16(data[$0 + 1]) << 8))
        }
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
