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

        SmartTranslationPromptStore.save("英文要更轻松，像日常聊天。", for: .chineseToEnglish)
        precondition(SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("更轻松"))
        precondition(!SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("不要油腻"))

        SmartTranslationPromptStore.reset(.chineseToEnglish)
        precondition(SmartTranslationDirection.chineseToEnglish.toneInstruction.contains("不要油腻"))
    }
}
