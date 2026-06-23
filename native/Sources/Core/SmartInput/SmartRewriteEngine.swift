import Foundation

protocol SmartRewriteEngine {
    var displayName: String { get }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext
    ) async throws -> SmartRewriteEngineOutput
}

final class NoopRewriteEngine: SmartRewriteEngine {
    let displayName = "原文"

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext
    ) async throws -> SmartRewriteEngineOutput {
        SmartRewriteEngineOutput(
            text: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            usage: nil
        )
    }
}

enum SmartRewriteError: Error {
    case timeout
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

    init(
        text: String,
        rawText: String,
        mode: RewriteMode,
        didFallback: Bool,
        modelName: String? = nil,
        usage: SmartUsage? = nil,
        normalizedText: String? = nil,
        termReplacements: [DeveloperTermReplacement] = []
    ) {
        self.text = text
        self.rawText = rawText
        self.mode = mode
        self.didFallback = didFallback
        self.modelName = modelName
        self.usage = usage
        self.normalizedText = normalizedText
        self.termReplacements = termReplacements
    }
}

struct SmartRewriteEngineOutput {
    let text: String
    let usage: SmartUsage?
}
