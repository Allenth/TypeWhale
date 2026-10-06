import Foundation

@main
struct SmartTranslationCheck {
    static func main() {
        SmartTranslationPromptStore.resetAll()
        defer { SmartTranslationPromptStore.resetAll() }

        let zhToEn = SmartTranslationDirection.fromMenuTag(0)
        precondition(zhToEn == .chineseToEnglish)
        precondition(zhToEn.displayName == "中译英")
        precondition(zhToEn.sourceLabel.contains("中文"))
        precondition(zhToEn.targetLabel == "English")
        precondition(zhToEn.toneInstruction.contains("真实聊天"))
        precondition(zhToEn.toneInstruction.contains("语气温柔"))
        precondition(zhToEn.toneInstruction.contains("不要油腻"))
        precondition(zhToEn.usesRawSourceTextForTranslation)

        let enToZh = SmartTranslationDirection.fromMenuTag(1)
        precondition(enToZh == .englishToChinese)
        precondition(enToZh.displayName == "英译中")
        precondition(enToZh.sourceLabel.contains("English"))
        precondition(enToZh.targetLabel.contains("中文"))
        precondition(enToZh.toneInstruction.contains("适合直接发送的中文"))
        precondition(!enToZh.usesRawSourceTextForTranslation)

        let emojiChat = SmartTranslationDirection.fromMenuTag(2)
        precondition(emojiChat == .chineseToEnglishEmojiChat)
        precondition(emojiChat.displayName == "中译英·多表情聊天")
        precondition(emojiChat.sourceLabel.contains("中文"))
        precondition(emojiChat.targetLabel == "English")
        precondition(emojiChat.toneInstruction.contains("semantic emoji"))
        precondition(emojiChat.toneInstruction.contains("普通短聊天可以用 1-4 个"))
        precondition(emojiChat.toneInstruction.contains("枚举/清单类句子"))
        precondition(emojiChat.toneInstruction.contains("5-10 个"))
        precondition(emojiChat.toneInstruction.contains("不要把 emoji 集中堆在句尾"))
        precondition(emojiChat.toneInstruction.contains("car 🚗"))
        precondition(emojiChat.toneInstruction.contains("trip ✈️"))
        precondition(emojiChat.toneInstruction.contains("flights ✈️"))
        precondition(emojiChat.toneInstruction.contains("packages 📦"))
        precondition(emojiChat.usesRawSourceTextForTranslation)

        SmartTranslationPromptStore.save("英文要更轻松，像日常聊天。", for: .chineseToEnglish)
        precondition(SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("更轻松"))
        precondition(!SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("不要油腻"))

        SmartTranslationPromptStore.reset(.chineseToEnglish)
        precondition(SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("不要油腻"))

        // 社交中译英分流
        SmartTranslationSocialScopeStore.reset()
        defer { SmartTranslationSocialScopeStore.reset() }

        let socialContext = SmartInputContext(targetAppName: "WeChat", targetBundleIdentifier: "com.tencent.xinWeChat")
        let devContext = SmartInputContext(targetAppName: "Xcode", targetBundleIdentifier: "com.apple.dt.Xcode")
        precondition(SmartTranslationSocialScopeStore.matches(socialContext))
        precondition(!SmartTranslationSocialScopeStore.matches(devContext))

        // 社交默认模板与常规不同，并升级为多表情聊天风格
        precondition(SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglish, social: true).contains("semantic emoji"))
        precondition(SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglishEmojiChat).contains("semantic emoji"))
        precondition(
            SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglish, social: true)
                != SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglish, social: false)
        )
        precondition(
            SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglish, social: true)
                == SmartTranslationPromptStore.defaultTemplate(for: .chineseToEnglishEmojiChat)
        )
        // 英译中没有社交变体，社交标记回退到常规模板
        precondition(
            SmartTranslationPromptStore.template(for: .englishToChinese, social: true)
                == SmartTranslationPromptStore.template(for: .englishToChinese, social: false)
        )

        // 社交模板独立存取，不影响常规中译英
        SmartTranslationPromptStore.save("社交英文更有网感 XYZ", for: .chineseToEnglish, social: true)
        precondition(SmartTranslationPromptStore.template(for: .chineseToEnglish, social: true).contains("XYZ"))
        precondition(!SmartTranslationPromptStore.template(for: .chineseToEnglish, social: false).contains("XYZ"))
        SmartTranslationPromptStore.reset(.chineseToEnglish, social: true)
        precondition(SmartTranslationPromptStore.template(for: .chineseToEnglish, social: true).contains("semantic emoji"))

        // 手动多表情聊天模板独立存取，不依赖目标窗口
        SmartTranslationPromptStore.save("emoji chat custom ABC", for: .chineseToEnglishEmojiChat)
        precondition(SmartTranslationPromptStore.template(for: .chineseToEnglishEmojiChat).contains("ABC"))
        precondition(!SmartTranslationPromptStore.template(for: .chineseToEnglish, social: true).contains("ABC"))
        SmartTranslationPromptStore.reset(.chineseToEnglishEmojiChat)
        precondition(SmartTranslationPromptStore.template(for: .chineseToEnglishEmojiChat).contains("semantic emoji"))

        // 语音中译英落到社交窗口用社交模板，其余走常规
        let socialPrompt = SmartTranslationPromptBuilder.prompt(
            source: "帮我看看这个功能", direction: .chineseToEnglish, context: socialContext, triggeredBy: "final_translation"
        )
        precondition(socialPrompt.contains("semantic emoji"))
        precondition(!socialPrompt.contains("整体感觉要像在 Slack"))

        let normalPrompt = SmartTranslationPromptBuilder.prompt(
            source: "帮我看看这个功能", direction: .chineseToEnglish, context: devContext, triggeredBy: "final_translation"
        )
        precondition(normalPrompt.contains("整体感觉要像在 Slack"))
        precondition(!normalPrompt.contains("semantic emoji"))
        precondition(normalPrompt.contains("必须把中文翻译成英文"))
        precondition(normalPrompt.contains("不要拒绝翻译"))
        precondition(normalPrompt.contains("cannot translate"))
        precondition(normalPrompt.contains("只允许输出英文译文"))

        // 手动多表情聊天模式不依赖社交窗口清单
        let forcedEmojiChatPrompt = SmartTranslationPromptBuilder.prompt(
            source: "我今天超级开心，生日派对很好玩", direction: .chineseToEnglishEmojiChat, context: devContext, triggeredBy: "final_translation"
        )
        precondition(forcedEmojiChatPrompt.contains("semantic emoji"))
        precondition(!forcedEmojiChatPrompt.contains("整体感觉要像在 Slack"))

        // 英译中忽略社交分流；截图翻译已经拆到 ScreenshotTranslationPromptBuilder，不再复用语音翻译 builder。
        let enzhPrompt = SmartTranslationPromptBuilder.prompt(
            source: "hello", direction: .englishToChinese, context: socialContext, triggeredBy: "final_translation"
        )
        precondition(!enzhPrompt.contains("semantic emoji"))
        let ignoredTriggeredByPrompt = SmartTranslationPromptBuilder.prompt(
            source: "[[TW_LINE_1]] hello", direction: .englishToChinese, context: socialContext, triggeredBy: "screenshot_translation"
        )
        precondition(ignoredTriggeredByPrompt.contains("语音翻译助手"))
        precondition(ignoredTriggeredByPrompt.contains("原始语音文本："))
        precondition(!ignoredTriggeredByPrompt.contains("截图 OCR 翻译助手"))
        precondition(!ignoredTriggeredByPrompt.contains("[[TW_LINE_n]]"))

        let refusal = """
        I'm sorry, but I cannot translate Chinese text into English as requested. My capabilities are limited to translating between languages and generating content in my native language (Chinese).
        """
        precondition(SmartRewriteOutputSanitizer.cleanTranslation(refusal).isEmpty)
    }
}
