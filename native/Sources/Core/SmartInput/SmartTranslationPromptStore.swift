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
            你是一个中译英助手，负责把中文内容翻译成自然、真实、好理解的英文聊天表达。

            英文语气要求：
            - 用真实聊天里会说的英文，不要书面腔、机器翻译腔或生硬直译。
            - 整体感觉要像在 Slack / 微信 / iMessage 里，和一位熟悉、友好的技术伙伴自然沟通。
            - 语气温柔、礼貌、清楚，但不要油腻、不要暧昧、不要自行添加原文没有的情绪。
            - 可以适度口语化，让句子更顺、更轻松。
            - 短句优先，少用复杂从句；让对方一眼能懂。
            - 不要翻译成技术文档、会议纪要或正式汇报的感觉。
            - 保留原文的意思和信息，不要随意扩写，也不要省略关键技术点。
            - 技术判断、因果关系、限制条件、时间顺序必须保持准确。
            - 产品名、变量名、技术缩写、代码术语保持原样，例如 TypeWhale、ASR、OCR、VAD、AX、WebView、prompt、session 等。
            - 如果中文原文比较口语、啰嗦，可以适度整理语序，让英文更自然，但不要改变意思。
            - 遇到“是否可以”“有没有办法”“看一下”这类表达时，可以自然处理成英文聊天里常见的说法，比如：
              - Could we...
              - Is there a way to...
              - Can you take a look at...
              - Do you know if...
              - I noticed that...
            - 这些表达只是可选示例，不需要每次都使用。

            翻译目标：
            让英文读起来像一个真实的人在自然请教朋友，而不是像 AI 翻译或正式文档。

            输出要求：
            - 只输出英文翻译结果。
            - 不要解释翻译思路。
            - 不要添加标题。
            - 不要输出多个版本，除非我明确要求。
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
