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
        let deepSeek = ProbeScreenshotTranslationEngine(
            displayName: "DeepSeek Screenshot Probe"
        )
        let qwen = ProbeScreenshotTranslationEngine(
            displayName: "Qwen Screenshot Probe"
        )
        let context = SmartInputContext(
            targetAppName: "截图翻译",
            targetBundleIdentifier: "TypeWhale.ScreenshotTranslation"
        )

        let remote = SelectedScreenshotTranslationEngine(
            deepSeek: deepSeek,
            managed: { model in
                precondition(model == .qwen3_4BInstruct2507_4bit)
                return qwen
            },
            modelProvider: { .deepSeekV4Flash }
        )
        let remoteOutput = try await remote.translateScreenshotOCR(
            rawText: "[[TW_LINE_1]] Settings",
            context: context
        )
        precondition(remote.displayName == "DeepSeek Screenshot Probe")
        precondition(
            remoteOutput.translatedText
                == "DeepSeek Screenshot Probe:[[TW_LINE_1]] Settings"
        )
        precondition(deepSeek.translateCalls == 1)

        var managedFactoryCalls = 0
        let local = SelectedScreenshotTranslationEngine(
            deepSeek: deepSeek,
            managed: { model in
                managedFactoryCalls += 1
                precondition(model == .qwen3_4BInstruct2507_4bit)
                return qwen
            },
            modelProvider: { .typeWhaleQwen3_4BInstruct }
        )
        let localOutput = try await local.translateScreenshotOCR(
            rawText: "[[TW_LINE_1]] Submit",
            context: context
        )
        precondition(local.displayName == "Qwen Screenshot Probe")
        precondition(managedFactoryCalls == 2)
        precondition(
            localOutput.translatedText
                == "Qwen Screenshot Probe:[[TW_LINE_1]] Submit"
        )
        precondition(qwen.translateCalls == 1)

        print("SelectedScreenshotTranslationEngineCheck passed")
    }
}
