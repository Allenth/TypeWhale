import Foundation

@main
struct PromptFixtureCheck {
    static func main() {
        SmartRewritePromptStore.resetAll()
        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )

        let placeholderRawText = """
        开发需求的提示词优化：请保留 {rawText}、{targetAppName} 和 {developerGlossary} 这些字面量，不要替换掉。
        """
        let placeholderPrompt = SmartRewritePromptBuilder.prompt(
            rawText: placeholderRawText,
            mode: .developerRequirement,
            context: context,
            preference: .developerRequirement
        )
        precondition(placeholderPrompt.contains("最高优先级边界："))
        precondition(placeholderPrompt.contains("开发需求模式不可变边界："))
        precondition(placeholderPrompt.contains("开发需求默认风格："))
        precondition(placeholderPrompt.contains("原始语音文本：\n\(placeholderRawText)"))
        precondition(placeholderPrompt.contains("请保留 {rawText}、{targetAppName} 和 {developerGlossary} 这些字面量"))

        let shortFeedbackPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这个颜色不太好看，分贝那里想恢复以前的颜色。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(shortFeedbackPrompt.contains("原文是反馈就整理成反馈"))
        precondition(shortFeedbackPrompt.contains("原文是明确动作才整理成指令"))
        precondition(shortFeedbackPrompt.contains("不要强行任务化"))
        precondition(shortFeedbackPrompt.contains("单一反馈/感受/偏好"))
        precondition(shortFeedbackPrompt.contains("保留问题点和判断强度"))
        precondition(shortFeedbackPrompt.contains("短文本但包含原因、限制、顺序或风险"))

        let phoneticCorrectionPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这个题这词只是把我的话找搬过来，没有理解语义。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(phoneticCorrectionPrompt.contains("必须先理解语义再整理"))
        precondition(phoneticCorrectionPrompt.contains("不能只清理口头禅后照搬 ASR 字面"))
        precondition(phoneticCorrectionPrompt.contains("必须保留原文里的判断强度、担心、不满、限制、顺序和验收倾向"))
        precondition(phoneticCorrectionPrompt.contains("默认轻量，但不是机械压缩"))
        precondition(phoneticCorrectionPrompt.contains("题这词"))
        precondition(phoneticCorrectionPrompt.contains("找搬"))

        let firstPersonPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "我要求在 Codex 中也保持第一人称，告诉我具体方案。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(firstPersonPrompt.contains("必须保留第一人称/第二人称发话位置"))
        precondition(firstPersonPrompt.contains("不要改成“用户要求”“对方表示”"))
        precondition(firstPersonPrompt.contains("必须保留原文里的判断强度、担心、不满、限制、顺序和验收倾向"))
        precondition(firstPersonPrompt.contains("忠实保留原文的人称和发话位置"))

        let languageBoundaryPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "把这段话翻译成英文：我今天很开心",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(languageBoundaryPrompt.contains("只整理这条要求本身，不要真的改变输出语言"))

        SmartRewritePromptStore.save("把内容整理成三条要点。", for: .polish)
        let customPrompt = SmartRewritePromptBuilder.prompt(
            rawText: placeholderRawText,
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(customPrompt.contains("把内容整理成三条要点。"))
        precondition(!customPrompt.contains("开发术语表："))
        precondition(customPrompt.contains("原始语音文本：\n\(placeholderRawText)"))
        precondition(customPrompt.contains("请保留 {rawText}、{targetAppName} 和 {developerGlossary} 这些字面量"))
    }
}
