import Foundation

struct SmartUsage: Codable, Equatable {
    private static let usdToCNYRate = 7.20

    let model: String?
    let mode: String?
    let requestID: String?
    let triggeredBy: String?
    let rawTextLength: Int?
    let promptLength: Int?
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let promptCacheHitTokens: Int
    let promptCacheMissTokens: Int
    let estimatedCostUSD: Double

    var estimatedCostCNY: Double {
        estimatedCostUSD * Self.usdToCNYRate
    }

    var compactText: String {
        String(format: "%d tok · 约¥%.6f", totalTokens, estimatedCostCNY)
    }

    var detailText: String {
        String(
            format: "本次用量 总计 %d tok · 输入 %d（缓存命中 %d / 未命中 %d）· 输出 %d · 估算费用 $%.8f / 约¥%.6f（按 v4-flash 单价折算，非官方账单）",
            totalTokens,
            promptTokens,
            promptCacheHitTokens,
            promptCacheMissTokens,
            completionTokens,
            estimatedCostUSD,
            estimatedCostCNY
        )
    }

    var requestLogText: String {
        [
            "request_id=\(requestID ?? "--")",
            "triggered_by=\(triggeredBy ?? "--")",
            "model=\(model ?? "--")",
            "mode=\(mode ?? "--")",
            "prompt_tokens=\(promptTokens)",
            "completion_tokens=\(completionTokens)",
            "total_tokens=\(totalTokens)",
            String(format: "estimated_cost=¥%.6f", estimatedCostCNY),
            "rawText_length=\(rawTextLength ?? -1)",
            "prompt_length=\(promptLength ?? -1)",
        ].joined(separator: " ")
    }

    static func deepSeekV4Flash(
        model: String = "deepseek-v4-flash",
        mode: String? = nil,
        requestID: String? = nil,
        triggeredBy: String? = nil,
        rawTextLength: Int? = nil,
        promptLength: Int? = nil,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        promptCacheHitTokens: Int,
        promptCacheMissTokens: Int
    ) -> SmartUsage {
        let inputCacheHitUSDPerMillion = 0.0028
        let inputCacheMissUSDPerMillion = 0.14
        let outputUSDPerMillion = 0.28
        // 保证每个输入 token 都计费：命中按命中价，其余（含接口未细分/漏报的部分）一律按未命中价，
        // 避免某次缺少缓存细分时把输入费用算成 0、只剩输出。
        let billedCacheHit = max(0, min(promptCacheHitTokens, promptTokens))
        let billedCacheMiss = max(promptCacheMissTokens, promptTokens - billedCacheHit)
        let cost =
            Double(billedCacheHit) / 1_000_000 * inputCacheHitUSDPerMillion +
            Double(billedCacheMiss) / 1_000_000 * inputCacheMissUSDPerMillion +
            Double(completionTokens) / 1_000_000 * outputUSDPerMillion
        return SmartUsage(
            model: model,
            mode: mode,
            requestID: requestID,
            triggeredBy: triggeredBy,
            rawTextLength: rawTextLength,
            promptLength: promptLength,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            promptCacheHitTokens: promptCacheHitTokens,
            promptCacheMissTokens: promptCacheMissTokens,
            estimatedCostUSD: cost
        )
    }

    static func combined(_ usages: [SmartUsage?]) -> SmartUsage? {
        let present = usages.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return SmartUsage(
            model: present.map { $0.model ?? "--" }.joined(separator: "+"),
            mode: present.map { $0.mode ?? "--" }.joined(separator: "+"),
            requestID: present.compactMap(\.requestID).joined(separator: "+"),
            triggeredBy: present.compactMap(\.triggeredBy).joined(separator: "+"),
            rawTextLength: present.compactMap(\.rawTextLength).max(),
            promptLength: present.compactMap(\.promptLength).reduce(0, +),
            promptTokens: present.reduce(0) { $0 + $1.promptTokens },
            completionTokens: present.reduce(0) { $0 + $1.completionTokens },
            totalTokens: present.reduce(0) { $0 + $1.totalTokens },
            promptCacheHitTokens: present.reduce(0) { $0 + $1.promptCacheHitTokens },
            promptCacheMissTokens: present.reduce(0) { $0 + $1.promptCacheMissTokens },
            estimatedCostUSD: present.reduce(0) { $0 + $1.estimatedCostUSD }
        )
    }
}
