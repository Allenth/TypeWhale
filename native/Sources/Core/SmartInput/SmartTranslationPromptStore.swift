import Foundation

enum SmartTranslationPromptStore {
    private static let keyPrefix = "smartTranslationPromptTemplate."

    static func template(for direction: SmartTranslationDirection) -> String {
        let saved = UserDefaults.standard.string(forKey: storageKey(for: direction)) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTemplate(for: direction) : saved
    }

    static func save(_ template: String, for direction: SmartTranslationDirection) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultTemplate(for: direction).trimmingCharacters(in: .whitespacesAndNewlines) {
            reset(direction)
        } else {
            UserDefaults.standard.set(template, forKey: storageKey(for: direction))
        }
    }

    static func reset(_ direction: SmartTranslationDirection) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: direction))
    }

    static func resetAll() {
        SmartTranslationDirection.allCases.forEach(reset)
    }

    static func defaultTemplate(for direction: SmartTranslationDirection) -> String {
        switch direction {
        case .chineseToEnglish:
            return """
            英文语气要求：
            - 用真实聊天里会说的英文，不要书面腔、机器翻译腔或生硬直译。
            - 语气温柔、礼貌、好理解，像在和关系友好的女性沟通。
            - 可以适度口语化，让句子更顺、更轻松，但不要油腻、不要夸张暧昧、不要自行添加原文没有的情绪。
            - 短句优先，少用复杂从句；让对方一眼能懂。
            """
        case .englishToChinese:
            return """
            中文语气要求：
            - 用自然、清楚、适合直接发送的中文。
            - 保留原文语气，不要过度润色或加入原文没有的情绪。
            """
        }
    }

    private static func storageKey(for direction: SmartTranslationDirection) -> String {
        keyPrefix + direction.rawValue
    }
}
