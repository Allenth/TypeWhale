import Foundation

enum FunASRSidecarCommand: String, Codable {
    case health
    case warmup
    case transcribe
    case shutdown
}

struct FunASRSidecarRequest: Codable, Equatable {
    let id: String
    let command: FunASRSidecarCommand
    let provider: String?
    let modelDirectory: String?
    let audioPath: String?
    let hotwords: [String]?
    let hotwordStrategy: String?

    init(
        id: String,
        command: FunASRSidecarCommand,
        provider: String? = nil,
        modelDirectory: String? = nil,
        audioPath: String? = nil,
        hotwords: [String]? = nil,
        hotwordStrategy: String? = nil
    ) {
        self.id = id
        self.command = command
        self.provider = provider
        self.modelDirectory = modelDirectory
        self.audioPath = audioPath
        self.hotwords = hotwords
        self.hotwordStrategy = hotwordStrategy
    }

    enum CodingKeys: String, CodingKey {
        case id, command, provider, hotwords
        case modelDirectory = "model_dir"
        case audioPath = "audio_path"
        case hotwordStrategy = "hotword_strategy"
    }
}

struct FunASRSidecarResponse: Codable, Equatable {
    let id: String
    let ok: Bool
    let ready: Bool?
    let text: String?
    let engine: String?
    let loadSeconds: Double?
    let durationSeconds: Double?
    let hotwordStrategy: String?
    let hotwordCount: Int?
    let error: String?
    let shutdown: Bool?

    enum CodingKeys: String, CodingKey {
        case id, ok, ready, text, engine, error, shutdown
        case loadSeconds = "load_sec"
        case durationSeconds = "duration_sec"
        case hotwordStrategy = "hotword_strategy"
        case hotwordCount = "hotword_count"
    }
}
