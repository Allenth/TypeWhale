import CryptoKit
import Foundation

struct TTSLabResultStore {
    private struct Record: Encodable {
        let timestamp: String
        let modelID: String
        let sampleID: String?
        let runtimeFingerprint: String?
        let weightFingerprint: String?
        let textSHA256: String
        let textCharacterCount: Int
        let metrics: TTSLabMetrics
        let outputFilename: String
        let voiceID: String?
    }

    private let resultsURL: URL
    private let fileManager: FileManager

    init(
        root: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("TypeWhale Pro/TTSLab/Results", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.resultsURL = root.appendingPathComponent("results.jsonl")
        self.fileManager = fileManager
    }

    func append(
        model: TTSLabModel,
        text: String,
        metrics: TTSLabMetrics,
        outputURL: URL,
        voiceID: String? = nil
    ) throws {
        try appendRecord(
            model: model,
            text: text,
            sampleID: nil,
            runtimeFingerprint: nil,
            weightFingerprint: nil,
            metrics: metrics,
            outputURL: outputURL,
            voiceID: voiceID
        )
    }

    func appendEvaluation(
        model: TTSLabModel,
        sample: TTSLabEvaluationSample,
        runtimeFingerprint: String,
        metrics: TTSLabMetrics,
        outputURL: URL
    ) throws {
        let manifest = model.directory.appendingPathComponent("typewhale-model.json")
        let fingerprint = (try? Data(contentsOf: manifest)).map(sha256)
        try appendRecord(
            model: model,
            text: sample.text,
            sampleID: sample.id,
            runtimeFingerprint: runtimeFingerprint,
            weightFingerprint: fingerprint,
            metrics: metrics,
            outputURL: outputURL,
            voiceID: nil
        )
    }

    private func appendRecord(
        model: TTSLabModel,
        text: String,
        sampleID: String?,
        runtimeFingerprint: String?,
        weightFingerprint: String?,
        metrics: TTSLabMetrics,
        outputURL: URL,
        voiceID: String?
    ) throws {
        try fileManager.createDirectory(
            at: resultsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let record = Record(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            modelID: model.id,
            sampleID: sampleID,
            runtimeFingerprint: runtimeFingerprint,
            weightFingerprint: weightFingerprint,
            textSHA256: sha256(Data(text.utf8)),
            textCharacterCount: text.count,
            metrics: metrics,
            outputFilename: outputURL.lastPathComponent,
            voiceID: voiceID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(record)
        line.append(0x0A)
        if !fileManager.fileExists(atPath: resultsURL.path) {
            try line.write(to: resultsURL, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: resultsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
