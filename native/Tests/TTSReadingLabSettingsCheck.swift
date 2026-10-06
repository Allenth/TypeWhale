import Foundation

@main
enum TTSReadingLabSettingsCheck {
    static func main() throws {
        let suite = "TTSReadingLabSettingsCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = TTSReadingLabSettingsStore(defaults: defaults)
        precondition(!settings.loadText().isEmpty)
        let input = "中文、emoji 🐋 and English\n第二行"
        settings.saveText(input)
        precondition(settings.loadText() == input)
        let voices = [
            TTSLabVoice(
                id: "voice-a",
                displayName: "Voice A",
                detail: "测试",
                group: .qwen,
                speakerID: nil,
                isDefault: true
            ),
            TTSLabVoice(
                id: "voice-b",
                displayName: "Voice B",
                detail: "测试",
                group: .qwen,
                speakerID: nil,
                isDefault: false
            ),
        ]
        precondition(
            settings.loadVoiceID(modelID: "model-a", availableVoices: voices) == "voice-a"
        )
        settings.saveVoiceID("voice-b", modelID: "model-a")
        precondition(
            settings.loadVoiceID(modelID: "model-a", availableVoices: voices) == "voice-b"
        )
        settings.saveVoiceID("missing", modelID: "model-a")
        precondition(
            settings.loadVoiceID(modelID: "model-a", availableVoices: voices) == "voice-a"
        )
        precondition(
            settings.loadVoiceID(modelID: "fixed-model", availableVoices: []) == nil
        )
        precondition(defaults.object(forKey: "ttsReadingLabState") == nil)
        precondition(defaults.object(forKey: "ttsReadingLabOutputURL") == nil)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTSReadingLabSettingsCheck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let model = TTSLabModel(
            id: "fake",
            displayName: "Fake",
            tier: 1,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: modelDirectory
        )
        let metrics = TTSLabMetrics(
            cold: true,
            prepareSeconds: 0.1,
            firstAudioSeconds: 0.2,
            synthesisSeconds: 0.3,
            audioSeconds: 1.5,
            rtf: 0.2,
            peakRSSBytes: 123_456
        )
        let store = TTSLabResultStore(root: root.appendingPathComponent("results"))
        try store.append(
            model: model,
            text: input,
            metrics: metrics,
            outputURL: root.appendingPathComponent("sample.wav"),
            voiceID: "voice-b"
        )
        try store.append(
            model: model,
            text: input,
            metrics: metrics,
            outputURL: root.appendingPathComponent("sample-2.wav")
        )
        let data = try Data(contentsOf: root.appendingPathComponent("results/results.jsonl"))
        let output = String(decoding: data, as: UTF8.self)
        let lines = output.split(separator: "\n")
        precondition(lines.count == 2)
        precondition(!output.contains(input))
        precondition(output.contains("\"textCharacterCount\":\(input.count)"))
        precondition(output.contains("\"textSHA256\":"))
        precondition(output.contains("\"outputFilename\":\"sample.wav\""))
        precondition(output.contains("\"voiceID\":\"voice-b\""))
        print("TTSReadingLabSettingsCheck passed")
    }
}
