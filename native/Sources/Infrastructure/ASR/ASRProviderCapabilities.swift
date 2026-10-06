import Foundation

struct ASRProviderCapability: Equatable {
    enum RecommendedUse: String {
        case fallback
        case finalCandidate
        case comparison
        case dependency
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
        case .senseVoice:
            return .init(
                id: "sensevoice-int8", displayName: "SenseVoice int8",
                supportsHotwords: false, supportsCodeSwitching: false,
                supportsStreaming: true, supportsLanguageHint: false,
                recommendedUse: .fallback, verificationStatus: .verifiedUnsupported,
                notes: "稳定中文实时识别主路，不支持热词。"
            )
        case .parakeetSherpa:
            return .init(
                id: "parakeet-tdt-0.6b-v2-sherpa-int8",
                displayName: "Parakeet TDT 0.6B v2 · Sherpa int8",
                supportsHotwords: false, supportsCodeSwitching: false,
                supportsStreaming: false, supportsLanguageHint: false,
                recommendedUse: .comparison, verificationStatus: .needsRuntimeValidation,
                notes: "英文轻量对照模型。"
            )
        case .funASRNano:
            return .init(
                id: "fun-asr-nano-2512", displayName: "Fun-ASR Nano",
                supportsHotwords: true, supportsCodeSwitching: true,
                supportsStreaming: false, supportsLanguageHint: true,
                recommendedUse: .finalCandidate, verificationStatus: .verifiedCandidate,
                notes: "本地最终识别；支持中英混合与音频侧 hotwords。"
            )
        case .qwen3MLX06B:
            return mlxCapability(
                id: "qwen3-asr-0.6b-mlx-8bit",
                name: "Qwen3-ASR 0.6B · MLX 8-bit"
            )
        case .qwen3MLX17B:
            return mlxCapability(
                id: "qwen3-asr-1.7b-mlx-8bit",
                name: "Qwen3-ASR 1.7B · MLX 8-bit"
            )
        }
    }

    static var managedModelCapabilities: [ASRProviderCapability] {
        ManagedASRModelCatalog.asrModels.map { capability(forManagedModelID: $0.id) }
    }

    static func capability(forManagedModelID id: String) -> ASRProviderCapability {
        switch id {
        case "fun-asr-nano-2512":
            return capability(for: .funASRNano)
        case "fsmn-vad":
            return .init(
                id: id, displayName: "FSMN-VAD",
                supportsHotwords: false, supportsCodeSwitching: false,
                supportsStreaming: true, supportsLanguageHint: false,
                recommendedUse: .dependency, verificationStatus: .notApplicable,
                notes: "只做 VAD 分段，不承担识别。"
            )
        default:
            return .init(
                id: id, displayName: id,
                supportsHotwords: false, supportsCodeSwitching: false,
                supportsStreaming: false, supportsLanguageHint: false,
                recommendedUse: .comparison, verificationStatus: .needsRuntimeValidation,
                notes: "未知 ASR 模型，必须先完成能力验证。"
            )
        }
    }

    private static func mlxCapability(id: String, name: String) -> ASRProviderCapability {
        .init(
            id: id, displayName: name,
            supportsHotwords: false, supportsCodeSwitching: true,
            supportsStreaming: false, supportsLanguageHint: true,
            recommendedUse: .comparison, verificationStatus: .needsRuntimeValidation,
            notes: "受管 MLX sidecar 最终识别；不传未经验证的热词参数。"
        )
    }
}
