import CryptoKit
import Foundation

struct SenseVoiceModelArtifact {
    let remoteName: String
    let installedName: String
    let sha256: String
    let expectedBytes: Int64
}

final class ModelInstallVerificationCache {
    private let queue = DispatchQueue(label: "com.waykingah.typewhale.model-install-cache")
    private var values: [String: Bool] = [:]

    func value(for key: String, compute: () -> Bool) -> Bool {
        queue.sync {
            if let cached = values[key] {
                return cached
            }
            let computed = compute()
            values[key] = computed
            return computed
        }
    }

    func set(_ value: Bool, for key: String) {
        queue.sync { values[key] = value }
    }
}

enum SenseVoiceModelManifest {
    static let directoryName = "sensevoice-native"
    static let requiredFreeBytes: Int64 = 1_000_000_000
    static let repository = ProcessInfo.processInfo.environment["TYPESPEAKER_MODEL_BASE_URL"]
        ?? "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"
    static let artifacts = [
        SenseVoiceModelArtifact(
            remoteName: "model.int8.onnx",
            installedName: "model.onnx",
            sha256: "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51",
            expectedBytes: 239_233_841
        ),
        SenseVoiceModelArtifact(
            remoteName: "tokens.txt",
            installedName: "tokens.txt",
            sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc",
            expectedBytes: 315_894
        ),
    ]
    private static let installedCache = ModelInstallVerificationCache()

    static var modelDirectory: URL {
        AppPaths.models.appendingPathComponent(directoryName)
    }

    static var bundledModelDirectory: URL {
        AppPaths.resources.appendingPathComponent("Models").appendingPathComponent(directoryName)
    }

    static var preferredModelDirectory: URL? {
        if isInstalled(at: bundledModelDirectory) {
            return bundledModelDirectory
        }
        if isInstalled(at: modelDirectory) {
            return modelDirectory
        }
        return nil
    }

    static func isInstalled(at directory: URL = modelDirectory) -> Bool {
        guard let cacheKey = cacheKey(for: directory) else { return false }
        return installedCache.value(for: cacheKey) {
            artifacts.allSatisfy { artifact in
                let url = directory.appendingPathComponent(artifact.installedName)
                return (try? sha256(of: url)) == artifact.sha256
            }
        }
    }

    static func rememberVerifiedInstallation(at directory: URL = modelDirectory) {
        guard let cacheKey = cacheKey(for: directory) else { return }
        installedCache.set(true, for: cacheKey)
    }

    private static func cacheKey(for directory: URL) -> String? {
        var cacheParts = [directory.path]
        for artifact in artifacts {
            let url = directory.appendingPathComponent(artifact.installedName)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == artifact.expectedBytes else { return nil }
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            cacheParts.append("\(artifact.installedName):\(size.int64Value):\(modified)")
        }
        return cacheParts.joined(separator: "|")
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum VoiceActivityModelManifest {
    static let directoryName = "vad"
    static let modelName = "silero_vad.onnx"
    static let sha256 = "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"
    static let expectedBytes: Int64 = 643_854
    private static let installedCache = ModelInstallVerificationCache()

    static var modelURL: URL {
        AppPaths.models.appendingPathComponent(directoryName).appendingPathComponent(modelName)
    }

    static var bundledModelURL: URL {
        AppPaths.resources
            .appendingPathComponent("Models")
            .appendingPathComponent(directoryName)
            .appendingPathComponent(modelName)
    }

    static var preferredModelURL: URL? {
        if isInstalled(at: bundledModelURL) {
            return bundledModelURL
        }
        if isInstalled(at: modelURL) {
            return modelURL
        }
        return nil
    }

    static func isInstalled(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value == expectedBytes else { return false }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.path)|\(size.int64Value)|\(modified)"
        return installedCache.value(for: cacheKey) {
            (try? SenseVoiceModelManifest.sha256(of: url)) == sha256
        }
    }
}

enum Qwen3ASRModelManifest {
    static let directoryName = "qwen3-asr-0.6b-int8"
    static let nestedDirectoryName = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
    static let requiredFiles = [
        "conv_frontend.onnx",
        "encoder.int8.onnx",
        "decoder.int8.onnx",
        "tokenizer/vocab.json",
        "tokenizer/merges.txt",
        "tokenizer/tokenizer_config.json",
    ]

    static var modelDirectory: URL {
        AppPaths.models
            .appendingPathComponent(directoryName)
            .appendingPathComponent(nestedDirectoryName)
    }

    static var bundledModelDirectory: URL {
        AppPaths.resources
            .appendingPathComponent("Models")
            .appendingPathComponent(directoryName)
            .appendingPathComponent(nestedDirectoryName)
    }

    static var preferredModelDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["TYPEWHALE_QWEN3_ASR_MODEL_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if isInstalled(at: url) { return url }
        }
        if isInstalled(at: bundledModelDirectory) {
            return bundledModelDirectory
        }
        if isInstalled(at: modelDirectory) {
            return modelDirectory
        }
        return nil
    }

    static func isInstalled(at directory: URL) -> Bool {
        requiredFiles.allSatisfy { relativePath in
            let url = directory.appendingPathComponent(relativePath)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
    }
}
