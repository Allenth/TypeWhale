import Foundation

struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let developerGlossary: String? = nil
}

@main
struct ManagedMLXLLMPrefillCheck {
    static func main() {
        let request = ManagedLLMPrefill.request(
            modelDirectory: URL(fileURLWithPath: "/managed/qwen")
        )

        precondition(request.command == .rewrite)
        precondition(
            request.systemPrompt
                == SmartRewriteSafetyPrompt.rewriteSystemPrompt(
                    lead: SmartRewriteSafetyPrompt.localRewriteLead
                )
        )
        precondition(
            request.userPrompt
                == SmartRewritePromptBuilder.cacheableUserPrefix
                    + "\n\n[[TYPEWHALE_STARTUP_PREFILL]]"
        )
        let productionPrompt = SmartRewritePromptBuilder.prompt(
            rawText: "检查首次真实整理是否复用生产提示词。",
            mode: .developerRequirement,
            context: SmartInputContext(
                targetAppName: "Codex",
                targetBundleIdentifier: "com.openai.codex"
            ),
            preference: .developerRequirement
        )
        precondition(
            productionPrompt.hasPrefix(
                SmartRewritePromptBuilder.cacheableUserPrefix
            )
        )
        precondition(SmartRewritePromptBuilder.cacheableUserPrefix.count > 250)
        precondition(SmartRewritePromptBuilder.cacheableUserPrefix.count < 800)
        precondition(request.maxTokens == 8)
        precondition(request.modelDirectory == "/managed/qwen")

        print("ManagedMLXLLMPrefillCheck passed")
    }
}
