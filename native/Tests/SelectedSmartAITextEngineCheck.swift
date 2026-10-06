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
        let deepSeek = ProbeAITextEngine(
            displayName: "DeepSeek Probe",
            logName: "deepseek",
            usesLocalCostGuard: true
        )
        let qwen = ProbeAITextEngine(
            displayName: "Qwen3 4B Probe",
            logName: "managed_mlx",
            usesLocalCostGuard: false
        )
        let context = SmartInputContext(
            targetAppName: "Test",
            targetBundleIdentifier: "test"
        )

        let remote = SelectedSmartAITextEngine(
            deepSeek: deepSeek,
            managed: { model in
                precondition(model == .qwen3_4BInstruct2507_4bit)
                return qwen
            },
            selectionProvider: { .deepSeekV4Flash }
        )
        precondition(remote.displayName == "DeepSeek Probe")
        precondition(remote.logName == "deepseek")
        precondition(remote.usesLocalCostGuard)
        _ = try await remote.rewrite(
            rawText: "hello",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(deepSeek.rewriteCalls == 1)

        var managedFactoryCalls = 0
        let local = SelectedSmartAITextEngine(
            deepSeek: deepSeek,
            managed: { model in
                managedFactoryCalls += 1
                precondition(model == .qwen3_4BInstruct2507_4bit)
                return qwen
            },
            selectionProvider: { .typeWhaleQwen3_4BInstruct }
        )
        precondition(local.displayName == "Qwen3 4B Probe")
        precondition(managedFactoryCalls == 1)
        precondition(local.logName == "managed_mlx")
        precondition(!local.usesLocalCostGuard)
        _ = try await local.rewrite(
            rawText: "本地整理",
            mode: .polish,
            context: context,
            preference: .polish
        )
        _ = try await local.translate(
            rawText: "本地翻译",
            direction: .chineseToEnglish,
            context: context,
            triggeredBy: "final_translation"
        )
        precondition(qwen.rewriteCalls == 1)
        precondition(qwen.translateCalls == 1)

        print("SelectedSmartAITextEngineCheck passed")
    }
}
