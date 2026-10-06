import Foundation

final class SelectedSmartAITextEngine: SmartAITextEngine {
    private let deepSeek: SmartAITextEngine
    private let managed: (ManagedLLMModelID) -> SmartAITextEngine
    private let selectionProvider: () -> SmartAIModel

    init(
        deepSeek: SmartAITextEngine = DeepSeekRewriteEngine(),
        managed: @escaping (ManagedLLMModelID) -> SmartAITextEngine = {
            ManagedLLMRuntimeService.shared.engine(for: $0)
        },
        selectionProvider: @escaping () -> SmartAIModel = { SmartAIModelStore.load() }
    ) {
        self.deepSeek = deepSeek
        self.managed = managed
        self.selectionProvider = selectionProvider
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
        let selection = selectionProvider()
        logRoute(selection, triggeredBy: "final_smart_rewrite")
        return try await engine(for: selection).rewrite(
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
        let selection = selectionProvider()
        logRoute(selection, triggeredBy: triggeredBy)
        return try await engine(for: selection).translate(
            rawText: rawText,
            direction: direction,
            context: context,
            triggeredBy: triggeredBy
        )
    }

    private var activeEngine: SmartAITextEngine {
        engine(for: selectionProvider())
    }

    private func engine(for model: SmartAIModel) -> SmartAITextEngine {
        switch model {
        case .typeWhaleQwen3_4BInstruct:
            return managed(.qwen3_4BInstruct2507_4bit)
        case .deepSeekV4Flash:
            return deepSeek
        }
    }

    private func logRoute(_ model: SmartAIModel, triggeredBy: String) {
        LaunchDiagnostics.mark(
            "smart_ai_route triggered_by=\(triggeredBy) provider=\(model.provider.rawValue) model=\(model.rawValue)"
        )
    }
}
