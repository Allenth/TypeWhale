import Foundation

@main
enum TTSLabWorkerVoiceCheck {
    static func main() throws {
        let workerURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let pythonURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTSLabWorkerVoiceCheck-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }

        let client = TTSLabWorkerClient(pythonURL: pythonURL, workerURL: workerURL)
        let model = TTSLabModel(
            id: "fake",
            displayName: "Fake",
            tier: 1,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: FileManager.default.temporaryDirectory
        )
        try client.start(model: model)
        _ = try client.prepare()
        let voice = TTSLabVoice(
            id: "test-voice",
            displayName: "Test",
            detail: "",
            group: .qwen,
            speakerID: nil,
            isDefault: true
        )
        let result = try client.synthesize(
            text: "你好 TypeWhale",
            outputURL: output,
            voice: voice
        )
        precondition(result.actualVoiceID == "test-voice")
        precondition(result.metrics.audioSeconds > 0)
        precondition(FileManager.default.fileExists(atPath: output.path))
        client.shutdown()
        print("TTSLabWorkerVoiceCheck passed")
    }
}
