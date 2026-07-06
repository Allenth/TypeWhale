import Foundation

enum ASRBackend: String {
    case automatic
    case senseVoice
    case qwen3ASR
}

@main
struct ASRProviderCapabilitiesCheck {
    static func main() {
        let senseVoice = ASRProviderCapabilities.capability(for: .senseVoice)
        precondition(senseVoice.id == "sensevoice-int8")
        precondition(senseVoice.supportsHotwords == false)
        precondition(senseVoice.supportsCodeSwitching == false)
        precondition(senseVoice.supportsStreaming == true)
        precondition(senseVoice.recommendedUse == .fallback)
        precondition(senseVoice.verificationStatus == .verifiedUnsupported)

        let qwen = ASRProviderCapabilities.capability(for: .qwen3ASR)
        precondition(qwen.id == "qwen3-asr-0.6b")
        precondition(qwen.supportsHotwords == false)
        precondition(qwen.supportsCodeSwitching == false)
        precondition(qwen.recommendedUse == .fallback)
        precondition(qwen.verificationStatus == .verifiedUnsupported)

        let automatic = ASRProviderCapabilities.capability(for: .automatic)
        precondition(automatic.id == "automatic")
        precondition(automatic.supportsHotwords == false)
        precondition(automatic.recommendedUse == .fallback)

        let managed = ASRProviderCapabilities.managedModelCapabilities
        precondition(managed.count == ManagedASRModelCatalog.models.count)
        precondition(Set(managed.map(\.id)).count == managed.count)

        let paraformerContextual = ASRProviderCapabilities.capability(forManagedModelID: "paraformer-hotword-contextual")
        precondition(paraformerContextual.supportsHotwords)
        precondition(!paraformerContextual.supportsCodeSwitching)
        precondition(paraformerContextual.recommendedUse == .finalCandidate)
        precondition(paraformerContextual.verificationStatus == .verifiedCandidate)

        let nano = ASRProviderCapabilities.capability(forManagedModelID: "fun-asr-nano-2512")
        precondition(nano.supportsHotwords)
        precondition(nano.supportsCodeSwitching)
        precondition(nano.recommendedUse == .sidecarCandidate)
        precondition(nano.verificationStatus == .needsRuntimeValidation)

        let paraformerZH = ASRProviderCapabilities.capability(forManagedModelID: "paraformer-zh")
        precondition(!paraformerZH.supportsHotwords)
        precondition(paraformerZH.supportsCodeSwitching)
        precondition(paraformerZH.recommendedUse == .comparison)

        let vad = ASRProviderCapabilities.capability(forManagedModelID: "fsmn-vad")
        precondition(!vad.supportsHotwords)
        precondition(vad.recommendedUse == .dependency)

        let punc = ASRProviderCapabilities.capability(forManagedModelID: "ct-punc")
        precondition(!punc.supportsHotwords)
        precondition(punc.recommendedUse == .postProcessing)

        print("ASRProviderCapabilitiesCheck passed")
    }
}
