import Foundation

struct ManagedASRModel: Equatable, Identifiable {
    enum Role: String {
        case primary
        case comparison
        case dependency
        case optional
    }

    let id: String
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
        ManagedASRModelCatalog.directoryContainsRegularFile(directory(in: rootDirectory), fileManager: fileManager)
    }
}

enum ManagedASRModelCatalog {
    static let rootDirectoryName = "funasr"

    static func rootDirectory(in modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent(rootDirectoryName, isDirectory: true)
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

    static let models: [ManagedASRModel] = [
        ManagedASRModel(
            id: "fun-asr-nano-2512",
            displayName: "Fun-ASR-Nano-2512",
            modelScopeID: "FunAudioLLM/Fun-ASR-Nano-2512",
            relativeDirectoryName: "fun-asr-nano-2512",
            role: .primary,
            sizeText: "约 2GB",
            estimatedBytes: 2_000_000_000,
            capabilityText: "中英混合 / hotwords",
            detailText: "LLM-ASR 主候选，官方 AutoModel 暴露 hotwords 参数。"
        ),
        ManagedASRModel(
            id: "paraformer-hotword-contextual",
            displayName: "Paraformer Contextual",
            modelScopeID: "damo/speech_paraformer-large-contextual_asr_nat-zh-cn-16k-common-vocab8404",
            relativeDirectoryName: "paraformer-hotword-contextual",
            role: .primary,
            sizeText: "约 1GB",
            estimatedBytes: 1_000_000_000,
            capabilityText: "中文热词 / --hotword",
            detailText: "Contextual hotword 主验证模型，用于确认解码侧热词召回。"
        ),
        ManagedASRModel(
            id: "paraformer-zh",
            displayName: "Paraformer zh",
            modelScopeID: "damo/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch",
            relativeDirectoryName: "paraformer-zh",
            role: .comparison,
            sizeText: "约 0.9GB",
            estimatedBytes: 900_000_000,
            capabilityText: "中文主路 / 对照",
            detailText: "非 contextual 对照组，用于比较普通 Paraformer 与热词模型差异。"
        ),
        ManagedASRModel(
            id: "fsmn-vad",
            displayName: "FSMN-VAD",
            modelScopeID: "damo/speech_fsmn_vad_zh-cn-16k-common-onnx",
            relativeDirectoryName: "fsmn-vad",
            role: .dependency,
            sizeText: "< 10MB",
            estimatedBytes: 10_000_000,
            capabilityText: "FunASR 分段依赖",
            detailText: "只做 VAD 分段，不承担热词识别。"
        ),
        ManagedASRModel(
            id: "ct-punc",
            displayName: "CT-Punc",
            modelScopeID: "damo/punc_ct-transformer_cn-en-common-vocab471067-large-onnx",
            relativeDirectoryName: "ct-punc",
            role: .optional,
            sizeText: "约 1.1GB",
            estimatedBytes: 1_100_000_000,
            capabilityText: "标点恢复 / 可延后",
            detailText: "改善最终文本可读性，第一轮热词召回不强依赖。"
        ),
    ]
}
