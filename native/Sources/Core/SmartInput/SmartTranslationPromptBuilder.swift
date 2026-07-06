import Foundation

enum SmartTranslationPromptBuilder {
    static func prompt(
        source: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String
    ) -> String {
        _ = triggeredBy

        // 中译英落到社交窗口时，改用社交提示词；其余场景保持常规语气模板。
        let social = direction == .chineseToEnglish
            && SmartTranslationSocialScopeStore.matches(context)
        let tone = SmartTranslationPromptStore.template(for: direction, social: social)

        return """
        你是 TypeWhale 的语音翻译助手。

        翻译方向：\(direction.displayName)
        任务：\(direction.targetLanguageInstruction)

        规则：
        - 只输出译文，不要输出原文、解释、标签或 Markdown。
        - 保留人名、产品名、模型名、代码、API、库名等必要专有名词。
        - 修正明显的语音识别错误，但不要新增原文没有的信息。
        - 语气自然，适合直接粘贴到当前输入框。

        \(tone)

        目标应用：\(context.targetAppName ?? "未知")

        原始语音文本：
        \(source)
        """
    }
}
