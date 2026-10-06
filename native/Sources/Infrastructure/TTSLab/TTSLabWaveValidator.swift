import Foundation

enum TTSLabWaveValidationError: LocalizedError, Equatable {
    case invalidContainer
    case unsupportedFormat
    case empty
    case silent
    case clipped
    case nonFinite

    var errorDescription: String? {
        switch self {
        case .invalidContainer: return "WAV 容器无效"
        case .unsupportedFormat: return "WAV 格式暂不支持"
        case .empty: return "WAV 没有音频帧"
        case .silent: return "WAV 为全静音"
        case .clipped: return "WAV 存在持续削波"
        case .nonFinite: return "WAV 包含 NaN 或 Inf"
        }
    }
}

struct TTSLabWaveValidationReport: Equatable {
    let frameCount: Int
    let peak: Double
    let rms: Double
    let isSilent: Bool
}

struct TTSLabWaveValidator {
    func validate(url: URL) throws -> TTSLabWaveValidationReport {
        let data = try Data(contentsOf: url)
        guard data.count >= 44,
              ascii(data, offset: 0, count: 4) == "RIFF",
              ascii(data, offset: 8, count: 4) == "WAVE" else {
            throw TTSLabWaveValidationError.invalidContainer
        }

        var format: UInt16?
        var channels: UInt16?
        var bitsPerSample: UInt16?
        var audioData: Data?
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = ascii(data, offset: offset, count: 4)
            let size = Int(readUInt32(data, offset: offset + 4))
            let contentOffset = offset + 8
            guard size >= 0, contentOffset + size <= data.count else {
                throw TTSLabWaveValidationError.invalidContainer
            }
            if chunkID == "fmt ", size >= 16 {
                format = readUInt16(data, offset: contentOffset)
                channels = readUInt16(data, offset: contentOffset + 2)
                bitsPerSample = readUInt16(data, offset: contentOffset + 14)
            } else if chunkID == "data" {
                audioData = data.subdata(in: contentOffset..<(contentOffset + size))
            }
            offset = contentOffset + size + (size % 2)
        }

        guard let format, let channels, channels > 0,
              let bitsPerSample, let audioData else {
            throw TTSLabWaveValidationError.invalidContainer
        }
        let samples: [Double]
        switch (format, bitsPerSample) {
        case (1, 16):
            samples = stride(from: 0, to: audioData.count - 1, by: 2).map {
                let raw = Int16(bitPattern: readUInt16(audioData, offset: $0))
                return Double(raw) / 32_768.0
            }
        case (3, 32):
            samples = stride(from: 0, to: audioData.count - 3, by: 4).map {
                let bits = readUInt32(audioData, offset: $0)
                return Double(Float(bitPattern: bits))
            }
        default:
            throw TTSLabWaveValidationError.unsupportedFormat
        }
        guard !samples.isEmpty else {
            throw TTSLabWaveValidationError.empty
        }
        guard samples.allSatisfy(\.isFinite) else {
            throw TTSLabWaveValidationError.nonFinite
        }

        let peak = samples.reduce(0) { max($0, abs($1)) }
        let rms = sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Double(samples.count))
        let clippedRatio = Double(samples.filter { abs($0) >= 0.999 }.count)
            / Double(samples.count)
        if clippedRatio > 0.05 {
            throw TTSLabWaveValidationError.clipped
        }
        let report = TTSLabWaveValidationReport(
            frameCount: samples.count / Int(channels),
            peak: peak,
            rms: rms,
            isSilent: peak < 0.000_1
        )
        if report.isSilent {
            throw TTSLabWaveValidationError.silent
        }
        return report
    }

    private func ascii(_ data: Data, offset: Int, count: Int) -> String {
        guard offset >= 0, offset + count <= data.count else { return "" }
        return String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii) ?? ""
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
