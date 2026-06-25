import AppKit
import Foundation

struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?
    let isSecureTextEntry: Bool
    let developerGlossary: String?
    let recordingSessionId: String?

    init(
        targetAppName: String?,
        targetBundleIdentifier: String?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil,
        recordingSessionId: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
        self.isSecureTextEntry = isSecureTextEntry
        self.developerGlossary = developerGlossary
        self.recordingSessionId = recordingSessionId
    }

    init(
        targetApp: NSRunningApplication?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil,
        recordingSessionId: String? = nil
    ) {
        self.init(
            targetAppName: targetApp?.localizedName,
            targetBundleIdentifier: targetApp?.bundleIdentifier,
            windowTitle: windowTitle,
            isSecureTextEntry: isSecureTextEntry,
            developerGlossary: developerGlossary,
            recordingSessionId: recordingSessionId
        )
    }

    func withDeveloperGlossary(_ glossary: String?) -> SmartInputContext {
        SmartInputContext(
            targetAppName: targetAppName,
            targetBundleIdentifier: targetBundleIdentifier,
            windowTitle: windowTitle,
            isSecureTextEntry: isSecureTextEntry,
            developerGlossary: glossary,
            recordingSessionId: recordingSessionId
        )
    }
}

final class SmartInputRouter {
    private let engine: SmartRewriteEngine
    private let normalizer: DeveloperTermNormalizer

    init(engine: SmartRewriteEngine, normalizer: DeveloperTermNormalizer = DeveloperTermNormalizer()) {
        self.engine = engine
        self.normalizer = normalizer
    }

    func progressInfo(
        preference: SmartRewritePreference,
        context: SmartInputContext
    ) -> SmartRewriteProgressInfo {
        let profile = RewriteProfile(
            mode: chooseMode(preference: preference, context: context),
            timeoutSeconds: 8.0
        )
        return SmartRewriteProgressInfo(
            mode: profile.mode,
            shouldRewrite: profile.shouldRewrite,
            modelName: engine.displayName,
            timeoutSeconds: profile.timeoutSeconds
        )
    }

    func rewrite(
        rawText: String,
        preference: SmartRewritePreference,
        context: SmartInputContext
    ) async -> SmartRewriteResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SmartRewriteResult(text: "", rawText: rawText, mode: .raw, didFallback: false)
        }

        let profile = RewriteProfile(
            mode: chooseMode(preference: preference, context: context),
            timeoutSeconds: 8.0
        )

        guard profile.shouldRewrite else {
            return SmartRewriteResult(text: trimmed, rawText: rawText, mode: profile.mode, didFallback: false)
        }

        let normalization = normalizer.normalize(trimmed, context: context)
        let normalizedText = normalization.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rewriteText = normalizedText.isEmpty ? trimmed : normalizedText
        let scopedGlossary = DeveloperLexiconStore.promptGlossary(
            matching: [trimmed, rewriteText].joined(separator: "\n"),
            maxTerms: 12
        )
        let rewriteContext = context.withDeveloperGlossary(scopedGlossary)
        let prompt = SmartRewritePromptBuilder.prompt(
            rawText: rewriteText,
            mode: profile.mode,
            context: rewriteContext,
            preference: preference
        )
        switch SmartRewriteCostGuard.check(
            rawText: rewriteText,
            prompt: prompt,
            triggeredBy: "final_smart_rewrite"
        ) {
        case .allowed:
            break
        case .blocked(let reason):
            LaunchDiagnostics.mark(
                "deepseek request_skipped triggered_by=final_smart_rewrite mode=\(profile.mode.displayName) reason=\(reason) rawText_length=\(rewriteText.count) prompt_length=\(prompt.count)"
            )
            return SmartRewriteResult(
                text: normalizedText.isEmpty ? trimmed : normalizedText,
                rawText: rawText,
                mode: profile.mode,
                didFallback: true,
                normalizedText: normalizedText,
                termReplacements: normalization.replacements,
                fallbackReason: Self.userFacingFallback(for: reason)
            )
        }

        do {
            let output = try await rewriteWithTimeout(
                rawText: rewriteText,
                mode: profile.mode,
                context: rewriteContext,
                timeoutSeconds: profile.timeoutSeconds
            )
            let rewritten = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // 结果为空仍按原文回退，但请求已计费——把 usage 直接记进账本，避免漏记（不污染转换记录行）。
            if rewritten.isEmpty {
                SmartUsageLedgerStore.record(output.usage)
            }
            return SmartRewriteResult(
                text: rewritten.isEmpty ? (normalizedText.isEmpty ? trimmed : normalizedText) : rewritten,
                rawText: rawText,
                mode: profile.mode,
                didFallback: rewritten.isEmpty,
                modelName: rewritten.isEmpty ? nil : engine.displayName,
                usage: rewritten.isEmpty ? nil : output.usage,
                normalizedText: normalizedText,
                termReplacements: normalization.replacements
            )
        } catch {
            return SmartRewriteResult(
                text: normalizedText.isEmpty ? trimmed : normalizedText,
                rawText: rawText,
                mode: profile.mode,
                didFallback: true,
                normalizedText: normalizedText,
                termReplacements: normalization.replacements
            )
        }
    }

    private static func userFacingFallback(for reason: String) -> String {
        if reason.hasPrefix("daily_cost_limit") {
            return String(format: "已达每日成本上限 ¥%.0f，已暂停整理，明天自动恢复", SmartRewriteCostGuard.dailyMaxCostCNY)
        }
        if reason.hasPrefix("daily_call_limit") {
            return "已达每日调用上限 \(SmartRewriteCostGuard.dailyMaxCalls) 次，已暂停整理，明天自动恢复"
        }
        if reason.hasPrefix("input_too_large") {
            return "这段文本过长，已直接粘贴原文（未整理）"
        }
        return "已暂停整理，已使用原文"
    }

    private func chooseMode(
        preference: SmartRewritePreference,
        context: SmartInputContext
    ) -> RewriteMode {
        if context.isSecureTextEntry {
            return .raw
        }
        if let manualMode = preference.manualMode {
            return manualMode
        }

        return SmartRewriteAutoRuleStore.mode(for: context)
    }

    private func rewriteWithTimeout(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        timeoutSeconds: TimeInterval
    ) async throws -> SmartRewriteEngineOutput {
        // 用独立 Task 发请求：超时只放弃等待、不取消请求，让它后台跑完并把已计费的 usage 补记进账本。
        // 否则超时的请求会被 DeepSeek 计费却不计入每日次数/成本，从而绕过成本上限。
        let work = Task { try await self.engine.rewrite(rawText: rawText, mode: mode, context: context) }
        do {
            return try await withThrowingTaskGroup(of: SmartRewriteEngineOutput.self) { group in
                group.addTask { try await work.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw SmartRewriteError.timeout
                }
                do {
                    let value = try await group.next() ?? SmartRewriteEngineOutput(text: rawText, usage: nil)
                    group.cancelAll()
                    return value
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } catch {
            Task {
                if let late = try? await work.value {
                    SmartUsageLedgerStore.record(late.usage)
                }
            }
            throw error
        }
    }
}

struct SmartRewriteProgressInfo {
    let mode: RewriteMode
    let shouldRewrite: Bool
    let modelName: String
    let timeoutSeconds: TimeInterval
}
