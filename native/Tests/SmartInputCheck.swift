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
    private(set) var lastRawText: String?

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        lastRawText = rawText
        lastMode = mode
        lastPreference = preference
        return SmartRewriteEngineOutput(text: rawText.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
    }
}

@main
struct SmartInputCheck {
    static func main() async {
        let autoRulesKey = "smartRewriteAutoConfiguration.v1"
        let lexiconKey = "developerLexicon.terms.v1"
        let originalAutoRules = UserDefaults.standard.data(forKey: autoRulesKey)
        let originalLexicon = UserDefaults.standard.data(forKey: lexiconKey)
        defer {
            if let originalAutoRules {
                UserDefaults.standard.set(originalAutoRules, forKey: autoRulesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: autoRulesKey)
            }
            if let originalLexicon {
                UserDefaults.standard.set(originalLexicon, forKey: lexiconKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lexiconKey)
            }
        }
        SmartRewriteAutoRuleStore.reset()
        DeveloperLexiconStore.restoreDefaults()
        let loadedTerms = DeveloperLexiconStore.load()
        let termNames = loadedTerms.map(\.canonical).joined(separator: ", ")
        precondition(
            loadedTerms.contains { $0.canonical == "Ollama" && $0.aliases.contains("ollama") },
            "Expected default lexicon to include Ollama, got \(termNames)"
        )
        precondition(!SmartRewriteAutoRuleStore.selectableModes.contains(.note))
        precondition(!SmartRewriteAutoRuleStore.selectableModes.contains(.chat))
        precondition(SmartRewriteAutoRuleStore.selectableModes.contains(.developerStatement))
        precondition(SmartRewriteAutoRuleStore.selectableModes.contains(.codeCommit))
        precondition(!SmartRewriteAutoRuleStore.defaultConfiguration.rules.contains { $0.mode == .note || $0.mode == .chat })
        precondition(!SmartRewriteAutoRuleStore.defaultConfiguration.rules.contains { $0.id == "notes" || $0.id == "chat" })

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

        let notesResult = await noopRouter.rewrite(
            rawText: "  今天随手记一下这个想法  ",
            preference: .automatic,
            context: SmartInputContext(targetAppName: "Notes", targetBundleIdentifier: "com.apple.Notes")
        )
        precondition(notesResult.mode == .polish)
        precondition(notesResult.text == "今天随手记一下这个想法")

        let chatResult = await noopRouter.rewrite(
            rawText: "  晚点发给你  ",
            preference: .automatic,
            context: SmartInputContext(targetAppName: "WeChat", targetBundleIdentifier: "com.tencent.xinWeChat")
        )
        precondition(chatResult.mode == .polish)
        precondition(chatResult.text == "晚点发给你")

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

        let directLoadedNormalization = DeveloperTermNormalizer().normalize(
            "用 ollma 检查 q wen 三点六 三十五 b",
            context: codex
        ).text
        precondition(
            directLoadedNormalization == "用 Ollama 检查 Qwen3.6 35B",
            "Expected loaded lexicon normalization, got \(directLoadedNormalization)"
        )

        let fuzzyCaptureEngine = CapturingRewriteEngine()
        let fuzzyCaptureRouter = SmartInputRouter(engine: fuzzyCaptureEngine)
        let fuzzyResult = await fuzzyCaptureRouter.rewrite(
            rawText: "  用 ollma 检查 q wen 三点六 三十五 b  ",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            fuzzyCaptureEngine.lastRawText == "用 Ollama 检查 Qwen3.6 35B",
            "Expected normalized text before model, got \(fuzzyCaptureEngine.lastRawText ?? "nil")"
        )
        precondition(
            fuzzyResult.text == "用 Ollama 检查 Qwen3.6 35B",
            "Expected normalized result, got \(fuzzyResult.text)"
        )

        let legacyJSON = """
        {
          "rules": [
            {
              "id": "notes",
              "title": "旧内置笔记规则",
              "keywords": ["notes"],
              "mode": "note",
              "isEnabled": true
            },
            {
              "id": "chat",
              "title": "旧内置聊天规则",
              "keywords": ["wechat"],
              "mode": "chat",
              "isEnabled": true
            },
            {
              "id": "legacy-custom",
              "title": "旧自定义规则",
              "keywords": ["custom"],
              "mode": "chat",
              "isEnabled": true
            }
          ],
          "fallbackMode": "chat"
        }
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacyJSON, forKey: autoRulesKey)
        let migrated = SmartRewriteAutoRuleStore.load()
        precondition(!migrated.rules.contains { $0.id == "notes" || $0.id == "chat" })
        let legacyRule = migrated.rules.first { $0.id == "legacy-custom" }
        precondition(legacyRule?.mode == .polish)
        precondition(legacyRule?.matchTarget == true)
        precondition(legacyRule?.matchContent == false)
        precondition(migrated.fallbackMode == .polish)
        precondition(migrated.rules.contains { $0.id == "summary-intent" && $0.matchContent && !$0.matchTarget })
    }
}
