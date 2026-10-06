import Foundation

struct TTSReadingLabSettingsStore {
    static let textKey = "ttsReadingLabText"
    static let voiceIDsByModelKey = "ttsReadingLabVoiceIDsByModel"
    static let defaultText = "你好，欢迎使用 TypeWhale 本地朗读测试。The quick brown fox jumps over the lazy dog."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadText() -> String {
        defaults.string(forKey: Self.textKey) ?? Self.defaultText
    }

    func saveText(_ text: String) {
        defaults.set(text, forKey: Self.textKey)
    }

    func loadVoiceID(
        modelID: String,
        availableVoices: [TTSLabVoice]
    ) -> String? {
        guard !availableVoices.isEmpty else { return nil }
        let saved = (defaults.dictionary(forKey: Self.voiceIDsByModelKey) as? [String: String])?[modelID]
        if let saved, availableVoices.contains(where: { $0.id == saved }) {
            return saved
        }
        return availableVoices.first(where: \.isDefault)?.id ?? availableVoices.first?.id
    }

    func saveVoiceID(_ voiceID: String, modelID: String) {
        var values = defaults.dictionary(forKey: Self.voiceIDsByModelKey) as? [String: String] ?? [:]
        values[modelID] = voiceID
        defaults.set(values, forKey: Self.voiceIDsByModelKey)
    }
}
