import Foundation

enum SmartRewriteCostGuard {
    static let maxInputTokens = 3_000
    static let maxOutputTokens = 400
    static let dailyMaxCalls = 120
    static let dailyMaxCostCNY = 1.00

    static func estimatedTokens(for text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 3.2)))
    }

    static func check(rawText: String, prompt: String, triggeredBy: String) -> SmartRewriteCostDecision {
        let rawTokens = estimatedTokens(for: rawText)
        let promptTokens = estimatedTokens(for: prompt)
        if rawTokens > maxInputTokens || promptTokens > maxInputTokens {
            return .blocked(
                reason: "input_too_large raw_tokens=\(rawTokens) prompt_tokens=\(promptTokens) limit=\(maxInputTokens)"
            )
        }
        if SmartUsageLedgerStore.todayCallCount >= dailyMaxCalls {
            return .blocked(
                reason: "daily_call_limit calls=\(SmartUsageLedgerStore.todayCallCount) limit=\(dailyMaxCalls)"
            )
        }
        if SmartUsageLedgerStore.todayCostCNY >= dailyMaxCostCNY {
            return .blocked(
                reason: String(format: "daily_cost_limit cost=¥%.6f limit=¥%.2f", SmartUsageLedgerStore.todayCostCNY, dailyMaxCostCNY)
            )
        }
        return .allowed(promptTokens: promptTokens, rawTokens: rawTokens, triggeredBy: triggeredBy)
    }
}

enum SmartRewriteCostDecision {
    case allowed(promptTokens: Int, rawTokens: Int, triggeredBy: String)
    case blocked(reason: String)
}
