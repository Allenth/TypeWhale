import Foundation

enum ASRCandidateID: String, CaseIterable, Codable, Hashable {
    case senseVoiceInt8 = "sensevoice-int8"
    case parakeetTDT06B = "parakeet-tdt-0.6b-v2-sherpa-int8"
    case funASRNano2512 = "fun-asr-nano-2512"
    case qwen3MLX06B = "qwen3-asr-0.6b-mlx-8bit"
    case qwen3MLX17B = "qwen3-asr-1.7b-mlx-8bit"
}

enum ASREngineKind: String, Codable {
    case sherpa
    case funASR
    case mlx
}

enum ASRHotwordStrategy: String, Codable, Equatable {
    case unsupported
    case nativeList
    case nativeSpaceSeparated
    case sherpaInline
    case contextPrompt
}

enum ASRReadiness: Equatable {
    case ready
    case validating
    case unavailable(String)
}

struct ASRModelDescriptor: Equatable {
    let id: ASRCandidateID
    let displayName: String
    let engine: ASREngineKind
    let modelDirectory: URL
    let requiredRelativePaths: [String]
    let hotwordStrategy: ASRHotwordStrategy
    let readiness: ASRReadiness
    let productionReady: Bool
}

struct ASREngineRequest {
    let runID: UUID
    let descriptor: ASRModelDescriptor
    let audioURL: URL
    let hotwords: ASRHotwordPayload
}

struct ASREngineResult {
    let text: String
    let engine: String
    let loadSeconds: Double
    let inferenceSeconds: Double
    let peakRSSMB: Double
}

struct ASRBenchmarkResult: Codable, Equatable, Identifiable {
    let id: UUID
    let sampleID: String
    let candidateID: ASRCandidateID
    let hotwordSnapshot: [String]
    let text: String
    let coldLoadSeconds: Double
    let firstInferenceSeconds: Double
    let warmInferenceSeconds: Double
    let audioDurationSeconds: Double
    let peakRSSMB: Double
    let createdAt: Date

    var realTimeFactor: Double { audioDurationSeconds > 0 ? warmInferenceSeconds / audioDurationSeconds : 0 }
    var hotwordHits: [String] { hotwordSnapshot.filter { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) } }
}
