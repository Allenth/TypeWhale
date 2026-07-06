import Foundation

struct ASRProviderCapability: Equatable {
    enum RecommendedUse: String {
        case fallback
        case finalCandidate
        case sidecarCandidate
        case comparison
        case dependency
        case postProcessing
    }

    enum VerificationStatus: String {
        case verifiedCandidate
        case needsRuntimeValidation
        case verifiedUnsupported
        case notApplicable
    }

    let id: String
    let displayName: String
    let supportsHotwords: Bool
    let supportsCodeSwitching: Bool
    let supportsStreaming: Bool
    let supportsLanguageHint: Bool
    let recommendedUse: RecommendedUse
    let verificationStatus: VerificationStatus
    let notes: String
}

enum ASRProviderCapabilities {
    static func capability(for backend: ASRBackend) -> ASRProviderCapability {
        switch backend {
        case .automatic:
            return ASRProviderCapability(
                id: "automatic",
                displayName: "自动",
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: true,
                supportsLanguageHint: false,
                recommendedUse: .fallback,
                verificationStatus: .verifiedUnsupported,
                notes: "自动模式只选择当前稳定 ASR fallback，不承诺 Pro 热词能力。"
            )
        case .senseVoice:
            return ASRProviderCapability(
                id: "sensevoice-int8",
                displayName: "SenseVoice int8",
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: true,
                supportsLanguageHint: false,
                recommendedUse: .fallback,
                verificationStatus: .verifiedUnsupported,
                notes: "当前稳定中文主路，不支持热词；只作为 Pro ASR 实验失败时的 fallback。"
            )
        case .qwen3ASR:
            return ASRProviderCapability(
                id: "qwen3-asr-0.6b",
                displayName: "Qwen3-ASR 0.6B",
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: false,
                supportsLanguageHint: false,
                recommendedUse: .fallback,
                verificationStatus: .verifiedUnsupported,
                notes: "当前本地 Qwen3-ASR 路径不能作为 Pro 中英混合热词主引擎。"
            )
        }
    }

    static var managedModelCapabilities: [ASRProviderCapability] {
        ManagedASRModelCatalog.models.map { capability(forManagedModelID: $0.id) }
    }

    static func capability(forManagedModelID id: String) -> ASRProviderCapability {
        switch id {
        case "fun-asr-nano-2512":
            return ASRProviderCapability(
                id: id,
                displayName: "Fun-ASR-Nano-2512",
                supportsHotwords: true,
                supportsCodeSwitching: true,
                supportsStreaming: false,
                supportsLanguageHint: true,
                recommendedUse: .sidecarCandidate,
                verificationStatus: .needsRuntimeValidation,
                notes: "LLM-ASR 中英混合候选；官方 AutoModel 暴露 hotwords，但本地 Python runtime 和 remote_code 仍需产品级验证。"
            )
        case "paraformer-hotword-contextual":
            return ASRProviderCapability(
                id: id,
                displayName: "Paraformer Contextual",
                supportsHotwords: true,
                supportsCodeSwitching: false,
                supportsStreaming: false,
                supportsLanguageHint: true,
                recommendedUse: .finalCandidate,
                verificationStatus: .verifiedCandidate,
                notes: "已确认 contextual hotword 能在解码/上下文阶段生效，优先作为开发术语热词召回候选。"
            )
        case "paraformer-zh":
            return ASRProviderCapability(
                id: id,
                displayName: "Paraformer zh",
                supportsHotwords: false,
                supportsCodeSwitching: true,
                supportsStreaming: false,
                supportsLanguageHint: true,
                recommendedUse: .comparison,
                verificationStatus: .needsRuntimeValidation,
                notes: "普通 Paraformer 对照组，用于比较 contextual hotword 模型带来的热词召回差异。"
            )
        case "fsmn-vad":
            return ASRProviderCapability(
                id: id,
                displayName: "FSMN-VAD",
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: true,
                supportsLanguageHint: false,
                recommendedUse: .dependency,
                verificationStatus: .notApplicable,
                notes: "只做 VAD 分段，不承担识别或热词召回。"
            )
        case "ct-punc":
            return ASRProviderCapability(
                id: id,
                displayName: "CT-Punc",
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: false,
                supportsLanguageHint: false,
                recommendedUse: .postProcessing,
                verificationStatus: .notApplicable,
                notes: "只做标点恢复，可改善最终文本可读性，不参与第一轮热词召回。"
            )
        default:
            return ASRProviderCapability(
                id: id,
                displayName: id,
                supportsHotwords: false,
                supportsCodeSwitching: false,
                supportsStreaming: false,
                supportsLanguageHint: false,
                recommendedUse: .comparison,
                verificationStatus: .needsRuntimeValidation,
                notes: "未知 ASR 模型，必须先完成能力验证。"
            )
        }
    }
}
