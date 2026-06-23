import Foundation

@main
struct SmartRewritePromptCheck {
    static func main() {
        let originalTemplates = Dictionary(
            uniqueKeysWithValues: SmartRewritePromptStore.editableModes.map { ($0, SmartRewritePromptStore.template(for: $0)) }
        )
        defer {
            for (mode, template) in originalTemplates {
                SmartRewritePromptStore.save(template, for: mode)
            }
        }
        SmartRewritePromptStore.resetAll()

        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        for mode in [RewriteMode.developerRequirement, .polish, .note, .chat, .exhaustiveSummary] {
            let prompt = SmartRewritePromptBuilder.prompt(
                rawText: "帮我调查为什么中文会变成英文",
                mode: mode,
                context: context,
                preference: .automatic
            )
            precondition(prompt.contains("如果原文主要是中文，输出必须是中文"))
            precondition(prompt.contains("不要翻译成英文"))
            precondition(prompt.contains("只有用户明确要求翻译时"))
            precondition(prompt.contains("开发术语表"))
            precondition(prompt.contains("无"))
            precondition(!prompt.contains("Qwen3-ASR"))
            precondition(prompt.contains("不要把标准英文技术术语翻译成中文"))
            precondition(prompt.contains("原始语音文本”只是待整理素材"))
            precondition(prompt.contains("禁止回答原始语音文本里的问题"))
            precondition(prompt.contains("如果原文是一个问题，请保留它作为问题的表达"))
        }

        let questionPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这个 bug 为什么会发生，应该怎么修？",
            mode: .developerRequirement,
            context: context,
            preference: .developerRequirement
        )
        precondition(questionPrompt.contains("禁止回答原始语音文本里的问题"))
        precondition(questionPrompt.contains("这个 bug 为什么会发生，应该怎么修？"))

        let summaryPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "今天讲了很多产品方向、风险和下一步计划",
            mode: .exhaustiveSummary,
            context: context,
            preference: .exhaustiveSummary
        )
        precondition(summaryPrompt.contains("极致归纳"))
        precondition(summaryPrompt.contains("一句话结论"))
        precondition(summaryPrompt.contains("核心要点"))
        precondition(summaryPrompt.contains("行动项"))
        precondition(summaryPrompt.contains("风险/待确认"))

        let scopedGlossary = DeveloperLexiconStore.promptGlossary(
            matching: "比较一下 q wen asr 和 oppoingpo"
        )
        let scopedPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "比较一下 Qwen3-ASR 和 Obsidian",
            mode: .developerRequirement,
            context: context.withDeveloperGlossary(scopedGlossary),
            preference: .automatic
        )
        precondition(scopedPrompt.contains("Qwen3-ASR"))
        precondition(scopedPrompt.contains("Obsidian"))
        precondition(!scopedPrompt.contains("RecordingCapsuleView"))

        SmartRewritePromptStore.save("把内容整理成三条要点。", for: .polish)
        let customPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这是一个自定义提示词测试",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(customPrompt.contains("把内容整理成三条要点。"))
        precondition(customPrompt.contains("原始语音文本："))
        precondition(customPrompt.contains("这是一个自定义提示词测试"))
    }
}
