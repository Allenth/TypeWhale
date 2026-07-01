import Foundation

enum SmartTranslationPromptStore {
    private static let keyPrefix = "smartTranslationPromptTemplate."

    /// 社交变体目前只对中译英开放；其余方向传 `social: true` 也回退到常规模板。
    static func supportsSocialVariant(_ direction: SmartTranslationDirection) -> Bool {
        direction == .chineseToEnglish
    }

    static func template(for direction: SmartTranslationDirection, social: Bool = false) -> String {
        let effectiveSocial = social && supportsSocialVariant(direction)
        let saved = UserDefaults.standard.string(forKey: storageKey(for: direction, social: effectiveSocial)) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTemplate(for: direction, social: effectiveSocial) : saved
    }

    static func save(_ template: String, for direction: SmartTranslationDirection, social: Bool = false) {
        let effectiveSocial = social && supportsSocialVariant(direction)
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty
            || trimmed == defaultTemplate(for: direction, social: effectiveSocial).trimmingCharacters(in: .whitespacesAndNewlines) {
            reset(direction, social: effectiveSocial)
        } else {
            UserDefaults.standard.set(template, forKey: storageKey(for: direction, social: effectiveSocial))
        }
    }

    static func reset(_ direction: SmartTranslationDirection, social: Bool = false) {
        let effectiveSocial = social && supportsSocialVariant(direction)
        UserDefaults.standard.removeObject(forKey: storageKey(for: direction, social: effectiveSocial))
    }

    static func resetAll() {
        for direction in SmartTranslationDirection.allCases {
            reset(direction)
            if supportsSocialVariant(direction) {
                reset(direction, social: true)
            }
        }
    }

    static func defaultTemplate(for direction: SmartTranslationDirection, social: Bool = false) -> String {
        if social && supportsSocialVariant(direction) {
            return socialChineseToEnglishTemplate
        }
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

    /// 社交中译英默认模板：面向公开社媒发帖/评论的英文风格。
    private static let socialChineseToEnglishTemplate = """
    你是一个中译英助手，负责把中文内容翻译成适合发到社交平台的自然英文。

    英文语气要求：
    - 面向 X / Threads / Instagram / 小红书 等公开社媒表达，轻松、真实、有网感。
    - 可以口语化、用常见缩写和自然的网络说法，但不要浮夸、不要硬凑俚语。
    - 短句优先、节奏轻快；可适度使用 emoji，但不堆叠、不喧宾夺主。
    - 保留原文的意思、态度和信息，不夸大、不新增情绪。
    - 产品名、变量名、技术缩写、代码术语保持原样，例如 TypeWhale、ASR、OCR、prompt 等。

    翻译目标：
    让英文读起来像一个真实的人在社交平台上自然发帖或评论，而不是像 AI 翻译或正式文档。

    输出要求：
    - 只输出英文翻译结果。
    - 不要解释翻译思路。
    - 不要添加标题。
    - 不要输出多个版本，除非我明确要求。
    """

    private static func storageKey(for direction: SmartTranslationDirection, social: Bool) -> String {
        keyPrefix + direction.rawValue + (social ? ".social" : "")
    }
}
