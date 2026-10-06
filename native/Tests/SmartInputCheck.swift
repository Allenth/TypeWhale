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

private final class FixedRewriteEngine: SmartRewriteEngine {
    let displayName = "Fixed Test Engine"
    private let output: String

    init(output: String) {
        self.output = output
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        SmartRewriteEngineOutput(text: output, usage: nil)
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
        precondition(SmartRewriteAutoRuleStore.selectableModes.contains(.chat))
        precondition(SmartRewritePreference.allCases.contains(.chat))
        precondition(!SmartRewritePreference.allCases.contains(.instantSummary))
        precondition(SmartRewritePreference.instantSummary.displayName == "即时归纳")
        precondition(SmartRewritePreference.instantSummary.manualMode == .note)
        precondition(RewriteMode.note.displayName == "即时归纳")
        precondition(SmartRewritePreference.chat.manualMode == .chat)
        precondition(SmartRewriteAutoRuleStore.selectableModes.contains(.developerStatement))
        precondition(SmartRewriteAutoRuleStore.selectableModes.contains(.codeCommit))
        precondition(!SmartRewriteAutoRuleStore.defaultConfiguration.rules.contains { $0.mode == .note })
        precondition(SmartRewriteAutoRuleStore.defaultConfiguration.rules.contains { $0.id == "social-chat" && $0.mode == .chat })
        precondition(!SmartRewriteAutoRuleStore.defaultConfiguration.rules.contains { $0.id == "notes" })

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

        let shortSummaryEngine = CapturingRewriteEngine()
        let shortSummaryRouter = SmartInputRouter(engine: shortSummaryEngine)
        let shortSummaryResult = await shortSummaryRouter.rewrite(
            rawText: "你要确保他成功。",
            preference: .exhaustiveSummary,
            context: codex
        )
        precondition(shortSummaryResult.mode == .exhaustiveSummary)
        precondition(shortSummaryResult.text == "你要确保他成功。")
        precondition(!shortSummaryResult.didFallback)
        precondition(shortSummaryResult.modelName == nil)
        precondition(shortSummaryEngine.lastRawText == nil)

        let instantSummaryResult = await noopRouter.rewrite(
            rawText: "  刚想到一个产品入口调整  ",
            preference: .instantSummary,
            context: codex
        )
        precondition(instantSummaryResult.mode == .note)
        precondition(instantSummaryResult.text == "刚想到一个产品入口调整")

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
        precondition(chatResult.mode == .chat)
        precondition(chatResult.text == "晚点发给你")

        let manualChatResult = await noopRouter.rewrite(
            rawText: "  晚点发给你  ",
            preference: .chat,
            context: codex
        )
        precondition(manualChatResult.mode == .chat)
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

        let modelOutput = "我的表达内容没有被准确理解和妥善处理，沟通中还存在曲解。"
        let directDeliveryRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: modelOutput)
        )
        let directDeliveryResult = await directDeliveryRouter.rewrite(
            rawText: "你说的这个方案让架构师过一遍。",
            preference: .developerRequirement,
            context: codex
        )
        precondition(!directDeliveryResult.didFallback)
        precondition(directDeliveryResult.text == String(modelOutput.dropLast()))

        let developerPeriodRouter = SmartInputRouter(
            engine: FixedRewriteEngine(
                output: "倒计时条与胶囊横向、纵向中心完全重合。"
            )
        )
        let developerPeriodResult = await developerPeriodRouter.rewrite(
            rawText: "倒计时条的位置要跟胶囊中心对齐",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            developerPeriodResult.text
                == "倒计时条与胶囊横向、纵向中心完全重合"
        )

        let englishPeriodRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: "Keep existing behavior.")
        )
        let englishPeriodResult = await englishPeriodRouter.rewrite(
            rawText: "Keep existing behavior",
            preference: .developerRequirement,
            context: codex
        )
        precondition(englishPeriodResult.text == "Keep existing behavior")

        let multiSentencePeriodRouter = SmartInputRouter(
            engine: FixedRewriteEngine(
                output: "第一项已经完成。第二项继续处理。"
            )
        )
        let multiSentencePeriodResult =
            await multiSentencePeriodRouter.rewrite(
                rawText: "第一项已经完成，第二项继续处理",
                preference: .developerRequirement,
                context: codex
            )
        precondition(
            multiSentencePeriodResult.text
                == "第一项已经完成。第二项继续处理"
        )

        let questionRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: "这个问题为什么会发生？")
        )
        let questionResult = await questionRouter.rewrite(
            rawText: "这个问题为什么会发生",
            preference: .developerRequirement,
            context: codex
        )
        precondition(questionResult.text == "这个问题为什么会发生？")

        let exclamationRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: "必须保留现有逻辑！")
        )
        let exclamationResult = await exclamationRouter.rewrite(
            rawText: "必须保留现有逻辑",
            preference: .developerRequirement,
            context: codex
        )
        precondition(exclamationResult.text == "必须保留现有逻辑！")

        let polishPeriodRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: "普通润色仍保留句号。")
        )
        let polishPeriodResult = await polishPeriodRouter.rewrite(
            rawText: "普通润色仍保留句号",
            preference: .polish,
            context: codex
        )
        precondition(polishPeriodResult.text == "普通润色仍保留句号")

        let ellipsisRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: "这个术语暂时不确定...")
        )
        let ellipsisResult = await ellipsisRouter.rewrite(
            rawText: "这个术语暂时不确定",
            preference: .developerRequirement,
            context: codex
        )
        precondition(ellipsisResult.text == "这个术语暂时不确定...")

        let equivalentConstraintOutput = "原文只说响应速度，不得改为影响速度。"
        let equivalentConstraintRouter = SmartInputRouter(
            engine: FixedRewriteEngine(output: equivalentConstraintOutput)
        )
        let equivalentConstraintResult = await equivalentConstraintRouter.rewrite(
            rawText: "原文只说响应速度，就不能改成影响速度。",
            preference: .exhaustiveSummary,
            context: codex
        )
        precondition(!equivalentConstraintResult.didFallback)
        precondition(
            equivalentConstraintResult.text
                == String(equivalentConstraintOutput.dropLast())
        )

        for mode in SmartRewritePromptStore.editableModes {
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "整理结果。",
                    mode: mode
                ) == "整理结果"
            )
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "Result.",
                    mode: mode
                ) == "Result"
            )
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "为什么？",
                    mode: mode
                ) == "为什么？"
            )
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "必须保留！",
                    mode: mode
                ) == "必须保留！"
            )
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "暂不确定...",
                    mode: mode
                ) == "暂不确定..."
            )
            precondition(
                SmartRewriteOutputSanitizer.finalize(
                    "第一句。第二句。",
                    mode: mode
                ) == "第一句。第二句"
            )
        }
        precondition(
            SmartRewriteOutputSanitizer.finalize(
                "原文。",
                mode: .raw
            ) == "原文。"
        )
        precondition(
            SmartRewriteOutputSanitizer.finalize(
                "命令。",
                mode: .command
            ) == "命令。"
        )

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

        let restartCaptureEngine = CapturingRewriteEngine()
        let restartRouter = SmartInputRouter(engine: restartCaptureEngine)
        _ = await restartRouter.rewrite(
            rawText: "倒计时条不显不显示取消按钮，点击整条后取消",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            restartCaptureEngine.lastRawText
                == "倒计时条不显示取消按钮，点击整条后取消"
        )

        let contrastCaptureEngine = CapturingRewriteEngine()
        let contrastRouter = SmartInputRouter(engine: contrastCaptureEngine)
        _ = await contrastRouter.rewrite(
            rawText: "不要因为他不听不信就改变原意",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            contrastCaptureEngine.lastRawText
                == "不要因为他不听不信就改变原意"
        )

        let parallelCaptureEngine = CapturingRewriteEngine()
        let parallelRouter = SmartInputRouter(engine: parallelCaptureEngine)
        _ = await parallelRouter.rewrite(
            rawText: "分贝颜色恢复以前，绿色镜框也恢复成以前的颜色",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            parallelCaptureEngine.lastRawText
                == "分贝颜色恢复以前。绿色镜框也恢复成以前的颜色"
        )

        let ordinaryCommaCaptureEngine = CapturingRewriteEngine()
        let ordinaryCommaRouter = SmartInputRouter(
            engine: ordinaryCommaCaptureEngine
        )
        _ = await ordinaryCommaRouter.rewrite(
            rawText: "取消按钮去掉，但提前按回车的逻辑继续保留",
            preference: .developerRequirement,
            context: codex
        )
        precondition(
            ordinaryCommaCaptureEngine.lastRawText
                == "取消按钮去掉，但提前按回车的逻辑继续保留"
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
        precondition(legacyRule?.mode == .chat)
        precondition(legacyRule?.matchTarget == true)
        precondition(legacyRule?.matchContent == false)
        precondition(migrated.appModesByBundleID.isEmpty)
        precondition(migrated.fallbackMode == .chat)
        precondition(migrated.rules.contains { $0.id == "summary-intent" && $0.matchContent && !$0.matchTarget })
        precondition(migrated.rules.contains { $0.id == "social-chat" && $0.mode == .chat })
    }
}
