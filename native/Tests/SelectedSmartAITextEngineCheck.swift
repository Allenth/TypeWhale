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
        let ollamaQwen35B = ProbeAITextEngine(displayName: "Ollama 35B Probe", logName: "ollama", usesLocalCostGuard: false)
        let ollamaQwen8B = ProbeAITextEngine(displayName: "Ollama 8B Probe", logName: "ollama", usesLocalCostGuard: false)
        let engine = SelectedSmartAITextEngine(
            deepSeek: deepSeek,
            ollama: { model in
                switch model {
                case .ollamaQwen35B: return ollamaQwen35B
                case .ollamaQwen8B: return ollamaQwen8B
                case .deepSeekV4Flash: return deepSeek
                }
            },
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
            triggeredBy: "final_translation"
        )
        precondition(translationOutput.translatedText == "DeepSeek Probe:Settings")
        precondition(deepSeek.translateCalls == 1)

        let localEngine = SelectedSmartAITextEngine(
            deepSeek: deepSeek,
            ollama: { model in
                switch model {
                case .ollamaQwen35B: return ollamaQwen35B
                case .ollamaQwen8B: return ollamaQwen8B
                case .deepSeekV4Flash: return deepSeek
                }
            },
            modelProvider: { .ollamaQwen35B }
        )
        precondition(localEngine.displayName == "Ollama 35B Probe")
        precondition(localEngine.logName == "ollama")
        precondition(!localEngine.usesLocalCostGuard)
        let localOutput = try await localEngine.rewrite(
            rawText: "本地整理",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(localOutput.text == "Ollama 35B Probe:本地整理")
        precondition(ollamaQwen35B.rewriteCalls == 1)
        print("SelectedSmartAITextEngineCheck passed")
    }
}
