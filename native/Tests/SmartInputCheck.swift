import Foundation

private final class SlowRewriteEngine: SmartRewriteEngine {
    let displayName = "Slow Test Engine"

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        try await Task.sleep(nanoseconds: 9_000_000_000)
        return SmartRewriteEngineOutput(text: "should-time-out", usage: nil)
    }
}

private final class CapturingRewriteEngine: SmartRewriteEngine {
    let displayName = "Capture Test Engine"
    private(set) var lastMode: RewriteMode?
    private(set) var lastPreference: SmartRewritePreference?

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        lastMode = mode
        lastPreference = preference
        return SmartRewriteEngineOutput(text: rawText.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
    }
}

@main
struct SmartInputCheck {
    static func main() async {
        let autoRulesKey = "smartRewriteAutoConfiguration.v1"
        let originalAutoRules = UserDefaults.standard.data(forKey: autoRulesKey)
        defer {
            if let originalAutoRules {
                UserDefaults.standard.set(originalAutoRules, forKey: autoRulesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: autoRulesKey)
            }
        }
        SmartRewriteAutoRuleStore.reset()

        let noopRouter = SmartInputRouter(engine: NoopRewriteEngine())

        let codex = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        let codexResult = await noopRouter.rewrite(
            rawText: "  我们看一下这个模型  ",
            preference: .automatic,
            context: codex
        )
        precondition(codexResult.mode == .developerRequirement)
        precondition(codexResult.text == "我们看一下这个模型")

        let terminal = SmartInputContext(
            targetAppName: "Terminal",
            targetBundleIdentifier: "com.apple.Terminal"
        )
        let terminalResult = await noopRouter.rewrite(
            rawText: "  git status  ",
            preference: .automatic,
            context: terminal
        )
        precondition(terminalResult.mode == .developerRequirement)
        precondition(terminalResult.text == "Git status")

        let xcode = SmartInputContext(
            targetAppName: "Xcode",
            targetBundleIdentifier: "com.apple.dt.Xcode"
        )
        let xcodeResult = await noopRouter.rewrite(
            rawText: "  修一下构建失败的问题  ",
            preference: .automatic,
            context: xcode
        )
        precondition(xcodeResult.mode == .developerRequirement)

        let manualResult = await noopRouter.rewrite(
            rawText: "  随便说一句  ",
            preference: .polish,
            context: terminal
        )
        precondition(manualResult.mode == .polish)
        precondition(manualResult.text == "随便说一句")

        let summaryResult = await noopRouter.rewrite(
            rawText: "  今天讲了产品方向、风险和下一步计划  ",
            preference: .exhaustiveSummary,
            context: codex
        )
        precondition(summaryResult.mode == .exhaustiveSummary)
        precondition(summaryResult.text == "今天讲了产品方向、风险和下一步计划")

        let automaticSummaryResult = await noopRouter.rewrite(
            rawText: "  帮我总结一下今天会议的要点和行动项  ",
            preference: .automatic,
            context: SmartInputContext(targetAppName: "Notes", targetBundleIdentifier: "com.apple.Notes")
        )
        precondition(automaticSummaryResult.mode == .exhaustiveSummary)
        precondition(automaticSummaryResult.text == "帮我总结一下今天会议的要点和行动项")

        let secureResult = await noopRouter.rewrite(
            rawText: "  secret  ",
            preference: .developerRequirement,
            context: SmartInputContext(
                targetAppName: "Any",
                targetBundleIdentifier: nil,
                isSecureTextEntry: true
            )
        )
        precondition(secureResult.mode == .raw)
        precondition(secureResult.text == "secret")

        let timeoutRouter = SmartInputRouter(engine: SlowRewriteEngine())
        let timeoutResult = await timeoutRouter.rewrite(
            rawText: "  需要回退  ",
            preference: .polish,
            context: codex
        )
        precondition(timeoutResult.didFallback)
        precondition(timeoutResult.text == "需要回退")

        let captureEngine = CapturingRewriteEngine()
        let captureRouter = SmartInputRouter(engine: captureEngine)
        _ = await captureRouter.rewrite(
            rawText: "  修掉智能整理偏好丢失的问题  ",
            preference: .developerRequirement,
            context: codex
        )
        precondition(captureEngine.lastMode == .developerRequirement)
        precondition(captureEngine.lastPreference == .developerRequirement)

        let legacyJSON = """
        {
          "rules": [
            {
              "id": "legacy-chat",
              "title": "旧聊天规则",
              "keywords": ["wechat"],
              "mode": "chat",
              "isEnabled": true
            }
          ],
          "fallbackMode": "polish"
        }
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacyJSON, forKey: autoRulesKey)
        let migrated = SmartRewriteAutoRuleStore.load()
        let legacyRule = migrated.rules.first { $0.id == "legacy-chat" }
        precondition(legacyRule?.matchTarget == true)
        precondition(legacyRule?.matchContent == false)
        precondition(migrated.rules.contains { $0.id == "summary-intent" && $0.matchContent && !$0.matchTarget })
    }
}
