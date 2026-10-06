import Foundation

final class SelectedScreenshotTranslationEngine: ScreenshotTranslationEngine {
    private let deepSeek: ScreenshotTranslationEngine
    private let managed: (ManagedLLMModelID) -> ScreenshotTranslationEngine
    private let modelProvider: () -> SmartAIModel

    init(
        deepSeek: ScreenshotTranslationEngine = DeepSeekRewriteEngine(),
        managed: @escaping (ManagedLLMModelID) -> ScreenshotTranslationEngine = {
            ManagedLLMRuntimeService.shared.screenshotEngine(for: $0)
        },
        modelProvider: @escaping () -> SmartAIModel = { SmartAIModelStore.load() }
    ) {
        self.deepSeek = deepSeek
        self.managed = managed
        self.modelProvider = modelProvider
    }

    var displayName: String {
        engine(for: modelProvider()).displayName
    }

    func translateScreenshotOCR(
        rawText: String,
        context: SmartInputContext
    ) async throws -> SmartTranslationOutput {
        let model = modelProvider()
        LaunchDiagnostics.mark("smart_ai_route triggered_by=\(ScreenshotTranslationPromptBuilder.triggeredBy) provider=\(model.provider.rawValue) model=\(model.rawValue)")
        return try await engine(for: model).translateScreenshotOCR(
            rawText: rawText,
            context: context
        )
    }

    private func engine(for model: SmartAIModel) -> ScreenshotTranslationEngine {
        switch model {
        case .typeWhaleQwen3_4BInstruct:
            return managed(.qwen3_4BInstruct2507_4bit)
        case .deepSeekV4Flash:
            return deepSeek
        }
    }
}
