import AVFAudio
import CryptoKit
import Foundation

struct TTSLabPersonalVoiceMetrics: Equatable {
    let duration: TimeInterval
    let peak: Float
    let rms: Float
    let clippedSampleRatio: Double
}

enum TTSLabPersonalVoiceValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case tooQuiet
    case clipped
    case unsupportedFormat
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .tooShort: return "录音太短，请完整读完引导句"
        case .tooLong: return "录音超过 3 秒，请按自然语速重录"
        case .tooQuiet: return "录音音量太小，请靠近麦克风重录"
        case .clipped: return "录音存在明显爆音，请稍微远离麦克风重录"
        case .unsupportedFormat: return "录音格式无法处理，请重新录制"
        case .damaged(let message): return "个人音色文件无效：\(message)"
        }
    }
}

struct TTSLabPersonalVoiceCandidate {
    let directoryURL: URL
    let referenceURL: URL
    let metrics: TTSLabPersonalVoiceMetrics
}

final class TTSLabPersonalVoiceStore {
    static let voiceID = "zipvoice-my-voice"
    static let referenceText = "清晰自然，稳定可靠。"

    private struct Manifest: Codable {
        let schemaVersion: Int
        let voiceID: String
        let experimental: Bool
        let durationSeconds: Double
        let sampleRate: Int
        let channels: Int
        let sampleWidthBytes: Int
        let rms: Double
        let clippedRatio: Double
        let audioSHA256: String
        let textSHA256: String
    }

    private let referencesRoot: URL
    private let fileManager: FileManager

    init(
        referencesRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "TypeWhale Pro/Models/tts/\(TTSLabVoiceCatalog.retainedModelID)/references",
            isDirectory: true
        ),
        fileManager: FileManager = .default
    ) {
        self.referencesRoot = referencesRoot
        self.fileManager = fileManager
    }

    func validateRecording(at sourceURL: URL) throws -> TTSLabPersonalVoiceMetrics {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        if duration < 1.0 { throw TTSLabPersonalVoiceValidationError.tooShort }
        if duration > 3.08 { throw TTSLabPersonalVoiceValidationError.tooLong }
        let metrics = try analyze(file: file, duration: duration)
        if metrics.rms < 0.008 || metrics.peak < 0.025 {
            throw TTSLabPersonalVoiceValidationError.tooQuiet
        }
        if metrics.clippedSampleRatio > 0.01 {
            throw TTSLabPersonalVoiceValidationError.clipped
        }
        return metrics
    }

    func prepareCandidate(from sourceURL: URL) throws -> TTSLabPersonalVoiceCandidate {
        _ = try validateRecording(at: sourceURL)
        try fileManager.createDirectory(at: referencesRoot, withIntermediateDirectories: true)
        let directory = referencesRoot.appendingPathComponent(
            ".\(Self.voiceID)-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let audioURL = directory.appendingPathComponent("reference.wav")
            try convertToZipVoiceFormat(sourceURL: sourceURL, destinationURL: audioURL)
            let metrics = try validateReference(at: audioURL)
            let textURL = directory.appendingPathComponent("reference.txt")
            try Data(Self.referenceText.utf8).write(to: textURL, options: .atomic)
            let manifest = Manifest(
                schemaVersion: 1,
                voiceID: Self.voiceID,
                experimental: true,
                durationSeconds: metrics.duration,
                sampleRate: 24_000,
                channels: 1,
                sampleWidthBytes: 2,
                rms: Double(metrics.rms),
                clippedRatio: metrics.clippedSampleRatio,
                audioSHA256: sha256(audioURL),
                textSHA256: sha256(textURL)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: directory.appendingPathComponent("reference.json"),
                options: .atomic
            )
            try validatePack(at: directory)
            return TTSLabPersonalVoiceCandidate(
                directoryURL: directory,
                referenceURL: audioURL,
                metrics: metrics
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func install(_ candidate: TTSLabPersonalVoiceCandidate) throws {
        try validatePack(at: candidate.directoryURL)
        let destination = installedDirectory
        let backup = referencesRoot.appendingPathComponent(
            ".\(Self.voiceID)-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadPrevious = fileManager.fileExists(atPath: destination.path)
        do {
            if hadPrevious { try fileManager.moveItem(at: destination, to: backup) }
            try fileManager.moveItem(at: candidate.directoryURL, to: destination)
            try validatePack(at: destination)
            if hadPrevious { try? fileManager.removeItem(at: backup) }
        } catch {
            try? fileManager.removeItem(at: destination)
            if hadPrevious, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    func discoverVoice() -> TTSLabVoice? {
        guard (try? validatePack(at: installedDirectory)) != nil else { return nil }
        return TTSLabVoice(
            id: Self.voiceID,
            displayName: "我的声音",
            detail: "本机录制 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: false
        )
    }

    func discard(_ candidate: TTSLabPersonalVoiceCandidate) {
        guard candidate.directoryURL.lastPathComponent.hasPrefix(".\(Self.voiceID)-staging-")
        else { return }
        try? fileManager.removeItem(at: candidate.directoryURL)
    }

    private var installedDirectory: URL {
        referencesRoot.appendingPathComponent(Self.voiceID, isDirectory: true)
    }

    private func validatePack(at directory: URL) throws {
        let audioURL = directory.appendingPathComponent("reference.wav")
        let textURL = directory.appendingPathComponent("reference.txt")
        let manifestURL = directory.appendingPathComponent("reference.json")
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw TTSLabPersonalVoiceValidationError.damaged("manifest 无法读取")
        }
        guard manifest.schemaVersion == 1,
              manifest.voiceID == Self.voiceID,
              manifest.sampleRate == 24_000,
              manifest.channels == 1,
              manifest.sampleWidthBytes == 2,
              sha256(audioURL) == manifest.audioSHA256,
              sha256(textURL) == manifest.textSHA256,
              (try? String(contentsOf: textURL, encoding: .utf8)) == Self.referenceText
        else {
            throw TTSLabPersonalVoiceValidationError.damaged("格式或哈希不匹配")
        }
        _ = try validateReference(at: audioURL)
    }

    private func validateReference(at url: URL) throws -> TTSLabPersonalVoiceMetrics {
        let file = try AVAudioFile(forReading: url)
        guard abs(file.fileFormat.sampleRate - 24_000) < 0.5,
              file.fileFormat.channelCount == 1 else {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        let duration = Double(file.length) / file.fileFormat.sampleRate
        if duration < 1.0 { throw TTSLabPersonalVoiceValidationError.tooShort }
        if duration > 3.08 { throw TTSLabPersonalVoiceValidationError.tooLong }
        let metrics = try analyze(file: file, duration: duration)
        if metrics.rms < 0.008 || metrics.peak < 0.025 {
            throw TTSLabPersonalVoiceValidationError.tooQuiet
        }
        if metrics.clippedSampleRatio > 0.01 {
            throw TTSLabPersonalVoiceValidationError.clipped
        }
        return metrics
    }

    private func analyze(file: AVAudioFile, duration: TimeInterval) throws
        -> TTSLabPersonalVoiceMetrics
    {
        file.framePosition = 0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        var peak: Float = 0
        var squared: Double = 0
        var sampleCount = 0
        var clipped = 0
        let input = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(min(file.length, 4096))
        )!
        while file.framePosition < file.length {
            input.frameLength = 0
            try file.read(into: input)
            if input.frameLength == 0 { break }
            let capacity = AVAudioFrameCount(
                ceil(Double(input.frameLength) * format.sampleRate / file.processingFormat.sampleRate)
            ) + 8
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            var consumed = false
            var conversionError: NSError?
            converter.convert(to: output, error: &conversionError) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return input
            }
            if let conversionError { throw conversionError }
            guard let channels = output.floatChannelData else { continue }
            for channel in 0..<Int(output.format.channelCount) {
                for index in 0..<Int(output.frameLength) {
                    let value = channels[channel][index]
                    peak = max(peak, abs(value))
                    squared += Double(value * value)
                    sampleCount += 1
                    if abs(value) >= 0.999 { clipped += 1 }
                }
            }
        }
        guard sampleCount > 0 else {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        return TTSLabPersonalVoiceMetrics(
            duration: duration,
            peak: peak,
            rms: Float(sqrt(squared / Double(sampleCount))),
            clippedSampleRatio: Double(clipped) / Double(sampleCount)
        )
    }

    private func convertToZipVoiceFormat(sourceURL: URL, destinationURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFile.processingFormat,
            to: outputFormat
        ) else {
            throw TTSLabPersonalVoiceValidationError.unsupportedFormat
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let input = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: 4096
        )!
        while inputFile.framePosition < inputFile.length {
            input.frameLength = 0
            try inputFile.read(into: input)
            if input.frameLength == 0 { break }
            let capacity = AVAudioFrameCount(
                ceil(Double(input.frameLength) * 24_000 / inputFile.processingFormat.sampleRate)
            ) + 16
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)!
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: output, error: &conversionError) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return input
            }
            if let conversionError { throw conversionError }
            try outputFile.write(from: output)
        }
    }

    private func sha256(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
