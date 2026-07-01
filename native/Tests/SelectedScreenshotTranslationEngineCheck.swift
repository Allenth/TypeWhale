import Foundation

private final class ProbeScreenshotTranslationEngine: ScreenshotTranslationEngine {
    let displayName: String
    private(set) var translateCalls = 0

    init(displayName: String) {
        self.displayName = displayName
    }

    func translateScreenshotOCR(
        rawText: String,
        context: SmartInputContext
    ) async throws -> SmartTranslationOutput {
        translateCalls += 1
        return SmartTranslationOutput(
            sourceText: rawText,
            translatedText: "\(displayName):\(rawText)",
            direction: .englishToChinese,
            modelName: displayName,
            usage: nil
        )
    }
}

@main
struct SelectedScreenshotTranslationEngineCheck {
    static func main() async throws {
        let deepSeek = ProbeScreenshotTranslationEngine(displayName: "DeepSeek Screenshot Probe")
        let ollama35B = ProbeScreenshotTranslationEngine(displayName: "Ollama Screenshot 35B Probe")
        let ollama8B = ProbeScreenshotTranslationEngine(displayName: "Ollama Screenshot 8B Probe")

        let remoteEngine = SelectedScreenshotTranslationEngine(
            deepSeek: deepSeek,
            ollama: { model in
                switch model {
                case .ollamaQwen35B: return ollama35B
                case .ollamaQwen8B: return ollama8B
                case .deepSeekV4Flash: return deepSeek
                }
            },
            modelProvider: { .deepSeekV4Flash }
        )
        let context = SmartInputContext(targetAppName: "截图翻译", targetBundleIdentifier: "TypeWhale.ScreenshotTranslation")
        let remoteOutput = try await remoteEngine.translateScreenshotOCR(
            rawText: "[[TW_LINE_1]] Settings",
            context: context
        )
        precondition(remoteEngine.displayName == "DeepSeek Screenshot Probe")
        precondition(remoteOutput.translatedText == "DeepSeek Screenshot Probe:[[TW_LINE_1]] Settings")
        precondition(remoteOutput.direction == .englishToChinese)
        precondition(deepSeek.translateCalls == 1)

        let localEngine = SelectedScreenshotTranslationEngine(
            deepSeek: deepSeek,
            ollama: { model in
                switch model {
                case .ollamaQwen35B: return ollama35B
                case .ollamaQwen8B: return ollama8B
                case .deepSeekV4Flash: return deepSeek
                }
            },
            modelProvider: { .ollamaQwen8B }
        )
        let localOutput = try await localEngine.translateScreenshotOCR(
            rawText: "[[TW_LINE_1]] Submit",
            context: context
        )
        precondition(localEngine.displayName == "Ollama Screenshot 8B Probe")
        precondition(localOutput.translatedText == "Ollama Screenshot 8B Probe:[[TW_LINE_1]] Submit")
        precondition(ollama8B.translateCalls == 1)

        print("SelectedScreenshotTranslationEngineCheck passed")
    }
}
