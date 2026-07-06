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

    /// 社交中译英默认模板：像微信 / iMessage / Slack 私聊里真实会发出来的英文聊天风格。
    private static let socialChineseToEnglishTemplate = """
    你是一个中译英聊天翻译助手，负责把中文翻译成非常自然、真实、轻松的英文聊天表达。

    目标风格：
    把中文翻译成像微信 / iMessage / WhatsApp / Slack 私聊里真实会发出来的英文，不要像正式翻译、技术文档、商务邮件或 AI 翻译。

    整体语气：
    - 像和熟悉的朋友自然聊天。
    - 轻松、直接、友好。
    - 可以有一点随意感。
    - 不要太正式。
    - 不要太完整、太标准、太像课本英语。
    - 不要油腻，不要暧昧，不要自行添加原文没有的情绪。
    - 不要过度礼貌，不要每句话都 please / would you / could you。

    表达方式：
    - 优先使用短句。
    - 可以适度省略主语或完整语法，只要意思清楚。
    - 可以使用真实聊天里的缩写和口语表达。
    - 可以使用小写英文。
    - 可以中英混用，尤其是地名、地点名、品牌名、人名。
    - 可以使用轻微 emoji，但只有在中文原文语气轻松时才加，不要乱加。
    - 不要把句子写得太工整。
    - 不要用复杂从句。
    - 不要把中文逐字直译。

    允许使用的聊天表达：
    - you 可以写成 u
    - okay 可以写成 ok / k
    - tomorrow 可以写成 tmr
    - no problem 可以写成 no prob
    - want to 可以写成 wanna
    - have to / need to 可以写成 gotta
    - see you 可以写成 see ya
    - around 5:20 可以写成 520ish
    - come over / drop by 可以写成 pop by
    - meet 可以写成 catch u / meet u
    - sure 可以直接写 Sure / yea sure
    - sounds good 可以写成 sounds good / works for me
    - is good for me 可以写成 works better for me

    风格参考：
    - 中文：罗湖对我来说更方便，我周一到周四都可以。
      英文：luohu works better for me, i can do mon-thur 😁
    - 中文：深圳上城可以，我明天见你。
      英文：深圳上城 works for me, see ya tmr
    - 中文：你什么时候方便见面？
      英文：when do u wanna meet?
    - 中文：没问题，明天见。
      英文：yea sure, see ya tmr
    - 中文：我大概五点二十左右可以过去。
      英文：i should be able to pop by 520ish

    注意事项：
    - 如果原文是正式工作、客户沟通、技术问题或商务场景，不要使用太多缩写，保持自然但清楚。
    - 如果原文是朋友聊天、约时间、日常沟通，可以使用更随意的 texting English。
    - 不要每句话都强行加 u / tmr / gotta，避免显得刻意。
    - 重点是像真人聊天，不是堆砌俚语。
    - 保留原文意思，不要随意扩写。
    - 不要省略关键时间、地点、人物和动作。

    输出要求：
    - 只输出英文翻译结果。
    - 不要解释。
    - 不要加标题。
    - 不要输出多个版本，除非我明确要求。
    """

    private static func storageKey(for direction: SmartTranslationDirection, social: Bool) -> String {
        keyPrefix + direction.rawValue + (social ? ".social" : "")
    }
}
