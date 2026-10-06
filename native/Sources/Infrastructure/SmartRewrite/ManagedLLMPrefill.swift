import Foundation

enum ManagedLLMPrefill {
    static let placeholder = "[[TYPEWHALE_STARTUP_PREFILL]]"
    static let maxTokens = 8
    static let rewriteSystemPrompt = SmartRewriteSafetyPrompt.rewriteSystemPrompt(
        lead: SmartRewriteSafetyPrompt.localRewriteLead
    )

    static func request(modelDirectory: URL) -> ManagedMLXLLMRequest {
        ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: UUID().uuidString,
            command: .rewrite,
            modelDirectory: modelDirectory.path,
            systemPrompt: rewriteSystemPrompt,
            userPrompt: SmartRewritePromptBuilder.cacheableUserPrefix
                + "\n\n"
                + placeholder,
            reasoning: .low,
            maxTokens: maxTokens
        )
    }
}
