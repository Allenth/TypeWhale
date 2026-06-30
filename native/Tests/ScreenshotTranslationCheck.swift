import AppKit
import Foundation

@main
struct ScreenshotTranslationCheck {
    static func main() {
        let context = SmartInputContext(
            targetAppName: "Safari",
            targetBundleIdentifier: "com.apple.Safari"
        )
        let screenshotPrompt = DeepSeekRewriteEngine.translationPrompt(
            source: """
            [[TW_LINE_1]] Settings
            [[TW_LINE_2]] Submit
            [[TW_LINE_3]] OpenAI API
            """,
            direction: .englishToChinese,
            context: context,
            triggeredBy: "screenshot_translation"
        )
        precondition(screenshotPrompt.contains("截图 OCR 翻译助手"))
        precondition(screenshotPrompt.contains("这是截图 OCR 文本，不是语音转写"))
        precondition(screenshotPrompt.contains("短词、按钮、菜单、标题、状态词也必须翻译"))
        precondition(screenshotPrompt.contains("不要因为英文很短"))
        precondition(screenshotPrompt.contains("无法确定上下文时，给出最可能的中文译法"))
        precondition(screenshotPrompt.contains("[[TW_LINE_n]]"))
        precondition(screenshotPrompt.contains("OCR 行文本："))
        precondition(!screenshotPrompt.contains("原始语音文本："))

        let ordinaryPrompt = DeepSeekRewriteEngine.translationPrompt(
            source: "Please send this tomorrow.",
            direction: .englishToChinese,
            context: context,
            triggeredBy: "final_translation"
        )
        precondition(ordinaryPrompt.contains("语音翻译助手"))
        precondition(ordinaryPrompt.contains("原始语音文本："))
        precondition(!ordinaryPrompt.contains("截图 OCR 翻译助手"))

        let compactRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 50, y: 40, width: 38, height: 18),
            text: "设置",
            selectionSize: NSSize(width: 300, height: 200)
        )
        precondition(compactRect.width < 80)
        precondition(compactRect.width >= 24)
        precondition(compactRect.height <= 34)
        precondition(abs(compactRect.minX - ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 300, height: 200))) <= 0.5)

        let longerRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 20, y: 80, width: 120, height: 20),
            text: "保存到配置的截图文件夹",
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(longerRect.width <= 160)
        precondition(longerRect.height <= 38)
        precondition(longerRect.minX >= 0)
        precondition(longerRect.maxX <= 320)
        precondition(abs(longerRect.minX - ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 320, height: 180))) <= 0.5)
        precondition(ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 100, height: 80)) == 5)
        precondition(ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 900, height: 500)) == 30)

        let backdropRect = ScreenshotTranslationLayout.backdropRect(
            sourceRects: [
                NSRect(x: 20, y: 80, width: 120, height: 20),
                NSRect(x: 22, y: 52, width: 88, height: 18),
            ],
            blockRects: [
                longerRect,
                NSRect(x: 20, y: 48, width: 96, height: 24),
            ],
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(backdropRect.minX <= ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 320, height: 180)))
        precondition(backdropRect.maxX >= longerRect.maxX)
        precondition(backdropRect.minY <= 44)
        precondition(backdropRect.maxY >= 104)
        precondition(backdropRect.maxX <= 320)
        precondition(backdropRect.maxY <= 180)
    }
}
