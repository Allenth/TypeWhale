import AppKit
import Foundation

struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?
    let isSecureTextEntry: Bool
    let developerGlossary: String?

    init(
        targetAppName: String?,
        targetBundleIdentifier: String?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
        self.isSecureTextEntry = isSecureTextEntry
        self.developerGlossary = developerGlossary
    }

    init(
        targetApp: NSRunningApplication?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil
    ) {
        self.init(
            targetAppName: targetApp?.localizedName,
            targetBundleIdentifier: targetApp?.bundleIdentifier,
            windowTitle: windowTitle,
            isSecureTextEntry: isSecureTextEntry,
            developerGlossary: developerGlossary
        )
    }

    func withDeveloperGlossary(_ glossary: String?) -> SmartInputContext {
        SmartInputContext(
            targetAppName: targetAppName,
            targetBundleIdentifier: targetBundleIdentifier,
            windowTitle: windowTitle,
            isSecureTextEntry: isSecureTextEntry,
            developerGlossary: glossary
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
            matching: [trimmed, rewriteText].joined(separator: "\n")
        )
        let rewriteContext = context.withDeveloperGlossary(scopedGlossary)

        do {
            let output = try await rewriteWithTimeout(
                rawText: rewriteText,
                mode: profile.mode,
                context: rewriteContext,
                timeoutSeconds: profile.timeoutSeconds
            )
            let rewritten = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        try await withThrowingTaskGroup(of: SmartRewriteEngineOutput.self) { group in
            group.addTask {
                try await self.engine.rewrite(rawText: rawText, mode: mode, context: context)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw SmartRewriteError.timeout
            }
            let value = try await group.next() ?? SmartRewriteEngineOutput(text: rawText, usage: nil)
            group.cancelAll()
            return value
        }
    }
}

struct SmartRewriteProgressInfo {
    let mode: RewriteMode
    let shouldRewrite: Bool
    let modelName: String
    let timeoutSeconds: TimeInterval
}
