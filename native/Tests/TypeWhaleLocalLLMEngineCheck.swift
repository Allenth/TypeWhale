import Foundation

private final class FakeManagedLLMRuntime: ManagedLLMRuntime {
    private(set) var requests: [ManagedMLXLLMRequest] = []
    var finalText = "我们再回顾一下下这个问题。"
    var error: Error?

    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        requests.append(request)
        if let error { throw error }
        return ManagedMLXLLMResponse(
            protocolVersion: 1,
            id: request.id,
            ok: true,
            finalText: finalText,
            errorCode: nil,
            errorMessage: nil,
            metrics: nil,
            cancelled: false
        )
    }

    func cancelCurrentRequest() {}
    func stop() {}
}

@main
struct TypeWhaleLocalLLMEngineCheck {
    static func main() async throws {
        let runtime = FakeManagedLLMRuntime()
        let modelDirectory = URL(
            fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit",
            isDirectory: true
        )
        let engine = TypeWhaleLocalLLMEngine(
            modelID: .qwen3_4BInstruct2507_4bit,
            runtime: runtime,
            modelDirectory: { modelDirectory },
            generationProfile: .init(maxOutputTokens: 512)
        )
        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )

        precondition(engine.displayName == "本地直驱 Qwen3 4B Instruct")
        precondition(engine.logName == "managed_mlx")
        precondition(!engine.usesLocalCostGuard)

        let rewrite = try await engine.rewrite(
            rawText: "我们再回顾一下下这个问题。",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(rewrite.text == "我们再回顾一下下这个问题。")
        precondition(rewrite.usage == nil)
        let rewriteRequest = runtime.requests[0]
        precondition(rewriteRequest.command == .rewrite)
        precondition(rewriteRequest.modelDirectory == modelDirectory.path)
        precondition(rewriteRequest.userPrompt == SmartRewritePromptBuilder.prompt(
            rawText: "我们再回顾一下下这个问题。",
            mode: .polish,
            context: context,
            preference: .polish
        ))
        precondition(rewriteRequest.systemPrompt.contains("只输出最终整理后的正文"))
        precondition(rewriteRequest.reasoning == .low)
        precondition(rewriteRequest.maxTokens == 512)

        runtime.finalText = "Open the model settings."
        let translation = try await engine.translate(
            rawText: "打开模型设置。",
            direction: .chineseToEnglish,
            context: context,
            triggeredBy: "final_translation"
        )
        precondition(translation.translatedText == "Open the model settings.")
        precondition(translation.modelName == "本地直驱 Qwen3 4B Instruct")
        precondition(translation.usage == nil)
        let translationRequest = runtime.requests[1]
        precondition(translationRequest.command == .translate)
        precondition(translationRequest.userPrompt == SmartTranslationPromptBuilder.prompt(
            source: "打开模型设置。",
            direction: .chineseToEnglish,
            context: context,
            triggeredBy: "final_translation"
        ))
        precondition(translationRequest.systemPrompt.contains("只输出最终译文"))

        runtime.finalText = "[[TW_LINE_1]] 设置"
        let screenshotTranslation = try await engine.translateScreenshotOCR(
            rawText: "[[TW_LINE_1]] Settings",
            context: context
        )
        precondition(screenshotTranslation.sourceText == "[[TW_LINE_1]] Settings")
        precondition(screenshotTranslation.translatedText == "[[TW_LINE_1]] 设置")
        precondition(screenshotTranslation.direction == .englishToChinese)
        precondition(screenshotTranslation.modelName == "本地直驱 Qwen3 4B Instruct")
        let screenshotRequest = runtime.requests[2]
        precondition(screenshotRequest.command == .translate)
        precondition(screenshotRequest.userPrompt == ScreenshotTranslationPromptBuilder.prompt(
            source: "[[TW_LINE_1]] Settings",
            context: context
        ))
        precondition(screenshotRequest.systemPrompt.contains("严格保留 [[TW_LINE_n]] 行号"))
        precondition(
            screenshotRequest.maxTokens
                == ScreenshotTranslationPromptBuilder.localMaxOutputTokens
        )

        runtime.error = ManagedLLMRuntimeError.helperExited
        do {
            _ = try await engine.rewrite(
                rawText: "保持原文",
                mode: .polish,
                context: context,
                preference: .polish
            )
            preconditionFailure("runtime failures must propagate to the existing router fallback")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .helperExited)
        }

        print("TypeWhaleLocalLLMEngineCheck passed")
    }
}
