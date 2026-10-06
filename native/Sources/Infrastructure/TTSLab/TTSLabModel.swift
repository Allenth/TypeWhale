import Foundation

enum TTSLabRuntime: String, Codable, Equatable {
    case sherpaONNX = "sherpa-onnx"
}

enum TTSLabQualification: String, Codable, Equatable {
    case passed
    case unverified
    case failed

    var displayName: String {
        switch self {
        case .passed: return "已验证"
        case .unverified: return "待验证"
        case .failed: return "验证失败"
        }
    }
}

enum TTSLabWeightState: String, Codable, Equatable {
    case installed
    case missing
}

enum TTSLabRuntimeReadiness: String, Codable, Equatable {
    case unknown
    case preparing
    case ready
    case failed
    case unavailable
}

struct TTSLabCapabilities: Codable, Equatable {
    let languages: [String]
    let supportsStreaming: Bool
    let supportsStyleControl: Bool

    static let basic = TTSLabCapabilities(
        languages: ["zh", "en"],
        supportsStreaming: false,
        supportsStyleControl: false
    )
}

struct TTSLabMetrics: Codable, Equatable {
    let cold: Bool
    let prepareSeconds: Double
    let firstAudioSeconds: Double
    let synthesisSeconds: Double
    let audioSeconds: Double
    let rtf: Double
    let peakRSSBytes: Int64
}

struct TTSLabModel: Equatable, Identifiable {
    let id: String
    let displayName: String
    let tier: Int
    let runtime: TTSLabRuntime
    let capabilities: TTSLabCapabilities
    let directory: URL
    let qualification: TTSLabQualification
    let weightState: TTSLabWeightState
    let runtimeReadiness: TTSLabRuntimeReadiness
    let defaultSpeakerID: Int
    let voices: [TTSLabVoice]

    init(
        id: String,
        displayName: String,
        tier: Int,
        runtime: TTSLabRuntime,
        capabilities: TTSLabCapabilities,
        directory: URL,
        qualification: TTSLabQualification = .unverified,
        weightState: TTSLabWeightState = .installed,
        runtimeReadiness: TTSLabRuntimeReadiness = .unknown,
        defaultSpeakerID: Int = 0,
        voices: [TTSLabVoice] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.tier = tier
        self.runtime = runtime
        self.capabilities = capabilities
        self.directory = directory
        self.qualification = qualification
        self.weightState = weightState
        self.runtimeReadiness = runtimeReadiness
        self.defaultSpeakerID = defaultSpeakerID
        self.voices = voices
    }

    func withRuntimeReadiness(_ readiness: TTSLabRuntimeReadiness) -> TTSLabModel {
        TTSLabModel(
            id: id,
            displayName: displayName,
            tier: tier,
            runtime: runtime,
            capabilities: capabilities,
            directory: directory,
            qualification: qualification,
            weightState: weightState,
            runtimeReadiness: readiness,
            defaultSpeakerID: defaultSpeakerID,
            voices: voices
        )
    }

    func withVoices(_ voices: [TTSLabVoice]) -> TTSLabModel {
        TTSLabModel(
            id: id,
            displayName: displayName,
            tier: tier,
            runtime: runtime,
            capabilities: capabilities,
            directory: directory,
            qualification: qualification,
            weightState: weightState,
            runtimeReadiness: runtimeReadiness,
            defaultSpeakerID: defaultSpeakerID,
            voices: voices
        )
    }
}
