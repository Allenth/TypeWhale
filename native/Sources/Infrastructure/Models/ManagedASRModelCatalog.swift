import Foundation

struct ManagedASRModel: Equatable, Identifiable {
    enum Kind: String {
        case asr
        case tts

        var displayName: String {
            switch self {
            case .asr: return "ASR"
            case .tts: return "TTS"
            }
        }

        var directoryPrefix: String {
            switch self {
            case .asr: return "funasr"
            case .tts: return "tts"
            }
        }
    }

    enum Role: String {
        case primary
        case comparison
        case dependency
        case optional
    }

    let id: String
    let kind: Kind
    let displayName: String
    let modelScopeID: String
    let relativeDirectoryName: String
    let role: Role
    let sizeText: String
    let estimatedBytes: Int64
    let capabilityText: String
    let detailText: String

    func directory(in rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent(relativeDirectoryName, isDirectory: true)
    }

    func isInstalled(in rootDirectory: URL, fileManager: FileManager = .default) -> Bool {
        let modelDirectory = directory(in: rootDirectory)
        guard let requiredPaths = ManagedASRModelCatalog.requiredRelativePathsByModelID[id] else {
            return false
        }
        return requiredPaths.allSatisfy { relativePath in
            let url = modelDirectory.appendingPathComponent(relativePath)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
    }
}

enum ManagedASRModelCatalog {
    static let requiredRelativePathsByModelID: [String: [String]] = [
        "fun-asr-nano-2512": [
            "model.pt",
            "config.yaml",
            "multilingual.tiktoken",
            "Qwen3-0.6B/config.json",
            "Qwen3-0.6B/tokenizer.json",
        ],
        "fsmn-vad": ["model_quant.onnx", "config.yaml", "am.mvn"],
    ]

    static func rootDirectory(in modelsDirectory: URL) -> URL {
        modelsDirectory
    }

    static func directoryContainsRegularFile(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return true
            }
        }
        return false
    }

    static let asrModels: [ManagedASRModel] = [
        ManagedASRModel(
            id: "fun-asr-nano-2512",
            kind: .asr,
            displayName: "Fun-ASR-Nano-2512",
            modelScopeID: "FunAudioLLM/Fun-ASR-Nano-2512",
            relativeDirectoryName: "funasr/fun-asr-nano-2512",
            role: .primary,
            sizeText: "约 2GB",
            estimatedBytes: 2_000_000_000,
            capabilityText: "中英混合 / hotwords",
            detailText: "LLM-ASR 主候选，官方 AutoModel 暴露 hotwords 参数。"
        ),
        ManagedASRModel(
            id: "fsmn-vad",
            kind: .asr,
            displayName: "FSMN-VAD",
            modelScopeID: "damo/speech_fsmn_vad_zh-cn-16k-common-onnx",
            relativeDirectoryName: "funasr/fsmn-vad",
            role: .dependency,
            sizeText: "< 10MB",
            estimatedBytes: 10_000_000,
            capabilityText: "FunASR 分段依赖",
            detailText: "只做 VAD 分段，不承担热词识别。"
        ),
    ]

    static let models: [ManagedASRModel] = asrModels
}
