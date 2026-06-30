import Foundation

final class SelectedSmartAITextEngine: SmartAITextEngine {
    private let deepSeek: SmartAITextEngine
    private let modelProvider: () -> SmartAIModel

    init(
        deepSeek: SmartAITextEngine = DeepSeekRewriteEngine(),
        modelProvider: @escaping () -> SmartAIModel = { SmartAIModelStore.load() }
    ) {
        self.deepSeek = deepSeek
        self.modelProvider = modelProvider
    }

    var displayName: String {
        activeEngine.displayName
    }

    var logName: String {
        activeEngine.logName
    }

    var usesLocalCostGuard: Bool {
        activeEngine.usesLocalCostGuard
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        let model = modelProvider()
        LaunchDiagnostics.mark("smart_ai_route triggered_by=final_smart_rewrite provider=\(model.provider.rawValue) model=\(model.rawValue)")
        return try await engine(for: model).rewrite(
            rawText: rawText,
            mode: mode,
            context: context,
            preference: preference
        )
    }

    func translate(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String = "final_translation"
    ) async throws -> SmartTranslationOutput {
        let model = modelProvider()
        LaunchDiagnostics.mark("smart_ai_route triggered_by=\(triggeredBy) provider=\(model.provider.rawValue) model=\(model.rawValue)")
        return try await engine(for: model).translate(
            rawText: rawText,
            direction: direction,
            context: context,
            triggeredBy: triggeredBy
        )
    }

    private var activeEngine: SmartAITextEngine {
        engine(for: modelProvider())
    }

    private func engine(for model: SmartAIModel) -> SmartAITextEngine {
        switch model {
        case .deepSeekV4Flash:
            return deepSeek
        }
    }
}
