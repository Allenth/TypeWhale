import Foundation

enum MLXASRSidecarCommand: String, Codable { case health, warmup, transcribe, shutdown }
struct MLXASRSidecarRequest: Codable, Equatable {
    let id: String; let command: MLXASRSidecarCommand; let provider: String?
    let modelDirectory: String?; let audioPath: String?; let contextPrompt: String?
    init(id: String, command: MLXASRSidecarCommand, provider: String? = nil, modelDirectory: String? = nil, audioPath: String? = nil, contextPrompt: String? = nil) {
        self.id=id; self.command=command; self.provider=provider; self.modelDirectory=modelDirectory; self.audioPath=audioPath; self.contextPrompt=contextPrompt
    }
    enum CodingKeys: String, CodingKey { case id, command, provider; case modelDirectory="model_dir"; case audioPath="audio_path"; case contextPrompt="context_prompt" }
}
struct MLXASRSidecarResponse: Codable, Equatable {
    let id: String; let ok: Bool; let ready: Bool?; let text: String?; let engine: String?
    let loadSeconds: Double?; let durationSeconds: Double?; let hotwordStrategy: String?; let error: String?; let shutdown: Bool?
    enum CodingKeys: String, CodingKey { case id, ok, ready, text, engine, error, shutdown; case loadSeconds="load_sec"; case durationSeconds="duration_sec"; case hotwordStrategy="hotword_strategy" }
}
