import Foundation

enum ASRBackend: String {
    case senseVoice
    case parakeetSherpa
    case funASRNano
    case qwen3MLX06B
    case qwen3MLX17B
}

@main
struct ASRProviderCapabilitiesCheck {
    static func main() {
        let senseVoice = ASRProviderCapabilities.capability(for: .senseVoice)
        precondition(senseVoice.id == "sensevoice-int8" && senseVoice.supportsStreaming)

        let nano = ASRProviderCapabilities.capability(for: .funASRNano)
        precondition(nano.id == "fun-asr-nano-2512")
        precondition(nano.supportsHotwords && nano.supportsCodeSwitching)
        precondition(nano.recommendedUse == .finalCandidate)

        let parakeet = ASRProviderCapabilities.capability(for: .parakeetSherpa)
        precondition(parakeet.id == "parakeet-tdt-0.6b-v2-sherpa-int8")
        precondition(!parakeet.supportsHotwords)

        for backend in [ASRBackend.qwen3MLX06B, .qwen3MLX17B] {
            precondition(!ASRProviderCapabilities.capability(for: backend).supportsHotwords)
        }

        let managed = ASRProviderCapabilities.managedModelCapabilities
        precondition(Set(managed.map(\.id)) == Set(["fun-asr-nano-2512", "fsmn-vad"]))
        precondition(ASRProviderCapabilities.capability(forManagedModelID: "fsmn-vad").recommendedUse == .dependency)
        print("ASRProviderCapabilitiesCheck passed")
    }
}
