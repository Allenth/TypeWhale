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
        precondition(placeholderPrompt.contains("开发需求最终动作："))
        precondition(placeholderPrompt.contains("开发需求目标："))
        precondition(placeholderPrompt.contains("原始语音文本：\n\(placeholderRawText)"))
        precondition(placeholderPrompt.contains("请保留 {rawText}、{targetAppName} 和 {developerGlossary} 这些字面量"))

        let shortFeedbackPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这个颜色不太好看，分贝那里想恢复以前的颜色。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(shortFeedbackPrompt.contains("原文是反馈就保留为反馈"))
        precondition(shortFeedbackPrompt.contains("原文明确要求动作时才整理成动作"))
        precondition(shortFeedbackPrompt.contains("反馈或疑问性质"))
        precondition(shortFeedbackPrompt.contains("事实保真优先于文风优化"))
        precondition(shortFeedbackPrompt.contains("原文是问题就保留为问题"))
        precondition(shortFeedbackPrompt.contains("不强套完整需求模板"))

        let countdownPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "两秒自动取消那个条不显不显示取消按钮，点击整条后取消它的位置正好跟胶囊是中心对齐的。",
            mode: .developerRequirement,
            context: context,
            preference: .developerRequirement
        )
        precondition(countdownPrompt.contains("先在内部理解，不要输出分析过程"))
        precondition(countdownPrompt.contains("对象、希望改变的行为、操作方式、状态或位置关系"))
        precondition(countdownPrompt.contains("要求保留的既有逻辑"))
        precondition(countdownPrompt.contains("“中心对齐”不得缩窄成“水平中心对齐”"))
        precondition(countdownPrompt.contains("清理明确语音噪声优先于原样保留"))
        precondition(countdownPrompt.contains("相邻的否定词和同一动作出现口吃式重复时"))
        precondition(countdownPrompt.contains("结合整句操作目的合并为一个明确动作"))
        precondition(countdownPrompt.contains("一句中包含多个并列的明确要求时"))
        precondition(countdownPrompt.contains("每项写成独立短句"))
        precondition(countdownPrompt.contains("不要添加“我理解你的需求是”"))
        precondition(countdownPrompt.contains("正文末尾不要添加中文句号或英文句点"))
        precondition(countdownPrompt.contains("开发需求最终动作："))
        precondition(countdownPrompt.contains("有明确口语赘余、重复或断裂语序时必须重组清楚"))
        precondition(countdownPrompt.contains("已经准确自然的短句不要硬改"))
        precondition(countdownPrompt.contains("并列要求分别表达"))
        precondition(countdownPrompt.contains("空间关系不得缩窄"))
        precondition(countdownPrompt.contains("保留第一人称/第二人称"))
        precondition(countdownPrompt.contains("两秒自动取消那个条不显不显示取消按钮"))

        let phoneticCorrectionPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "这个题这词只是把我的话找搬过来，没有理解语义。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(phoneticCorrectionPrompt.contains("先理解语义，再写成"))
        precondition(phoneticCorrectionPrompt.contains("不能只删口头禅后照搬字面"))
        precondition(phoneticCorrectionPrompt.contains("担心、不满、限制、顺序、验收倾向"))
        precondition(phoneticCorrectionPrompt.contains("判断不准时保留原话，不根据读音猜词"))
        precondition(phoneticCorrectionPrompt.contains("题这词"))
        precondition(phoneticCorrectionPrompt.contains("找搬"))

        let firstPersonPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "我要求在 Codex 中也保持第一人称，告诉我具体方案。",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(firstPersonPrompt.contains("保留第一人称/第二人称"))
        precondition(firstPersonPrompt.contains("不要写成第三人称总结"))
        precondition(firstPersonPrompt.contains("担心、不满、限制、顺序、验收倾向"))
        precondition(firstPersonPrompt.contains("忠实保留原文的人称、主体、指代"))

        let languageBoundaryPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "把这段话翻译成英文：我今天很开心",
            mode: .developerRequirement,
            context: context,
            preference: .automatic
        )
        precondition(languageBoundaryPrompt.contains("只整理这条语言转换需求，不要真的改变输出语言"))

        let fixedRecordingText = """
        先看最近三次录音日志，再判断问题在语音识别、智能整理还是粘贴阶段。GPT 和 ChatGPT 不同，Codex 和 Xcode 不能混在一起。第一，保存原始识别结果；第二，记录整理后的结果；第三，比较差异；最后决定是否修改提示词。不要扩写成新的技术方案。
        """
        let developerFixture = SmartRewritePromptBuilder.prompt(
            rawText: fixedRecordingText,
            mode: .developerRequirement,
            context: context,
            preference: .developerRequirement
        )
        precondition(developerFixture.contains("事实保真优先于文风优化"))
        precondition(developerFixture.contains("必须把每一步单独换行并使用编号"))
        let summaryFixture = SmartRewritePromptBuilder.prompt(
            rawText: fixedRecordingText,
            mode: .exhaustiveSummary,
            context: context,
            preference: .exhaustiveSummary
        )
        precondition(summaryFixture.contains("保留关键事实、限制、时间和行动顺序"))
        precondition(summaryFixture.contains("不同事实、名称、数字、时间、否定、疑问、人称、限制、风险和行动项不得合并或删除"))
        precondition(summaryFixture.contains("问题只能压缩为更短的问题表达，不能得到答案"))
        precondition(summaryFixture.contains("代答、方案或语言转换请求只能保留为请求"))
        precondition(summaryFixture.contains("每个被禁止的动作都要保留"))
        precondition(summaryFixture.contains("时间对照的前后两项必须完整保留"))

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
