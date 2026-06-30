import Foundation

private final class ProbeAITextEngine: SmartAITextEngine {
    let displayName: String
    let logName: String
    let usesLocalCostGuard: Bool
    private(set) var rewriteCalls = 0
    private(set) var translateCalls = 0

    init(displayName: String, logName: String, usesLocalCostGuard: Bool) {
        self.displayName = displayName
        self.logName = logName
        self.usesLocalCostGuard = usesLocalCostGuard
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        rewriteCalls += 1
        return SmartRewriteEngineOutput(text: "\(displayName):\(rawText)", usage: nil)
    }

    func translate(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String
    ) async throws -> SmartTranslationOutput {
        translateCalls += 1
        return SmartTranslationOutput(
            sourceText: rawText,
            translatedText: "\(displayName):\(rawText)",
            direction: direction,
            modelName: displayName,
            usage: nil
        )
    }
}

@main
struct SelectedSmartAITextEngineCheck {
    static func main() async throws {
        let deepSeek = ProbeAITextEngine(displayName: "DeepSeek Probe", logName: "deepseek", usesLocalCostGuard: true)
        let engine = SelectedSmartAITextEngine(
            deepSeek: deepSeek,
            modelProvider: { .deepSeekV4Flash }
        )
        let context = SmartInputContext(targetAppName: "Test", targetBundleIdentifier: "test")

        precondition(engine.displayName == "DeepSeek Probe")
        precondition(engine.logName == "deepseek")
        precondition(engine.usesLocalCostGuard)
        let deepSeekOutput = try await engine.rewrite(
            rawText: "hello",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(deepSeekOutput.text == "DeepSeek Probe:hello")
        precondition(deepSeek.rewriteCalls == 1)
        let translationOutput = try await engine.translate(
            rawText: "Settings",
            direction: .englishToChinese,
            context: context,
            triggeredBy: "screenshot_translation"
        )
        precondition(translationOutput.translatedText == "DeepSeek Probe:Settings")
        precondition(deepSeek.translateCalls == 1)
        print("SelectedSmartAITextEngineCheck passed")
    }
}
