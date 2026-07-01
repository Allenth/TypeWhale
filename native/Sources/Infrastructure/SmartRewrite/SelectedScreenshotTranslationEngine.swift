import Foundation

final class SelectedScreenshotTranslationEngine: ScreenshotTranslationEngine {
    private let deepSeek: ScreenshotTranslationEngine
    private let ollama: (SmartAIModel) -> ScreenshotTranslationEngine
    private let modelProvider: () -> SmartAIModel

    init(
        deepSeek: ScreenshotTranslationEngine = DeepSeekRewriteEngine(),
        ollama: @escaping (SmartAIModel) -> ScreenshotTranslationEngine = { OllamaRewriteEngine(model: $0) },
        modelProvider: @escaping () -> SmartAIModel = { SmartAIModelStore.load() }
    ) {
        self.deepSeek = deepSeek
        self.ollama = ollama
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
        case .ollamaQwen35B, .ollamaQwen8B:
            return ollama(model)
        case .deepSeekV4Flash:
            return deepSeek
        }
    }
}
