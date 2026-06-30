import Foundation

protocol SmartRewriteEngine {
    var displayName: String { get }
    var logName: String { get }
    var usesLocalCostGuard: Bool { get }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput
}

extension SmartRewriteEngine {
    var logName: String { "ai" }
    var usesLocalCostGuard: Bool { true }
}

protocol SmartTranslationEngine {
    var displayName: String { get }

    func translate(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String
    ) async throws -> SmartTranslationOutput
}

protocol SmartAITextEngine: SmartRewriteEngine, SmartTranslationEngine {}

final class NoopRewriteEngine: SmartRewriteEngine {
    let displayName = "原文"
    let usesLocalCostGuard = false

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        SmartRewriteEngineOutput(
            text: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            usage: nil
        )
    }
}

enum SmartRewriteError: Error {
    case timeout
    case costLimitExceeded(String)
}

struct SmartRewriteResult {
    let text: String
    let rawText: String
    let mode: RewriteMode
    let didFallback: Bool
    let modelName: String?
    let usage: SmartUsage?
    let normalizedText: String?
    let termReplacements: [DeveloperTermReplacement]
    /// 触发熔断/限额而回退时的用户可读说明；普通回退（超时等）为 nil。
    let fallbackReason: String?

    init(
        text: String,
        rawText: String,
        mode: RewriteMode,
        didFallback: Bool,
        modelName: String? = nil,
        usage: SmartUsage? = nil,
        normalizedText: String? = nil,
        termReplacements: [DeveloperTermReplacement] = [],
        fallbackReason: String? = nil
    ) {
        self.text = text
        self.rawText = rawText
        self.mode = mode
        self.didFallback = didFallback
        self.modelName = modelName
        self.usage = usage
        self.normalizedText = normalizedText
        self.termReplacements = termReplacements
        self.fallbackReason = fallbackReason
    }
}

struct SmartRewriteEngineOutput {
    let text: String
    let usage: SmartUsage?
}
