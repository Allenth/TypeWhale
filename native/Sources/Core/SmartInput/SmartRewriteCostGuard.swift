import Foundation

enum SmartRewriteCostGuard {
    // 这些是"异常熔断"阈值，不是日常节流：正常重度使用永远碰不到，只在程序失控时兜底。
    static let maxInputTokens = 8_000
    // 仅为上限，按实际生成的 token 计费；放高只是避免长口述被截断，不会凭空增加成本。
    static let maxOutputTokens = 4_000
    static let dailyMaxCalls = 1_000
    static let dailyMaxCostCNY = 6.00

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
