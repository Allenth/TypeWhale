import Foundation

enum SherpaASRSidecarCommand: String, Codable { case health, warmup, transcribe, shutdown }

struct SherpaASRSidecarRequest: Codable, Equatable {
    let id: String
    let command: SherpaASRSidecarCommand
    let provider: String?
    let modelDirectory: String?
    let audioPath: String?

    init(id: String, command: SherpaASRSidecarCommand, provider: String? = nil, modelDirectory: String? = nil, audioPath: String? = nil) {
        self.id = id; self.command = command; self.provider = provider
        self.modelDirectory = modelDirectory; self.audioPath = audioPath
    }

    enum CodingKeys: String, CodingKey {
        case id, command, provider
        case modelDirectory = "model_dir"
        case audioPath = "audio_path"
    }
}

struct SherpaASRSidecarResponse: Codable, Equatable {
    let id: String
    let ok: Bool
    let ready: Bool?
    let text: String?
    let engine: String?
    let loadSeconds: Double?
    let durationSeconds: Double?
    let error: String?
    let shutdown: Bool?

    enum CodingKeys: String, CodingKey {
        case id, ok, ready, text, engine, error, shutdown
        case loadSeconds = "load_sec"
        case durationSeconds = "duration_sec"
    }
}
