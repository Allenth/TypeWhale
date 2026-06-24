import Foundation

struct SmartUsage: Codable, Equatable {
    private static let usdToCNYRate = 7.20

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
        String(format: "%d tok · ¥%.6f", totalTokens, estimatedCostCNY)
    }

    var detailText: String {
        String(
            format: "总计 %d tok · 输入 %d（缓存命中 %d / 未命中 %d）· 输出 %d · 估算 $%.8f / ¥%.6f",
            totalTokens,
            promptTokens,
            promptCacheHitTokens,
            promptCacheMissTokens,
            completionTokens,
            estimatedCostUSD,
            estimatedCostCNY
        )
    }

    static func deepSeekV4Flash(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        promptCacheHitTokens: Int,
        promptCacheMissTokens: Int
    ) -> SmartUsage {
        let inputCacheHitUSDPerMillion = 0.0028
        let inputCacheMissUSDPerMillion = 0.14
        let outputUSDPerMillion = 0.28
        let cost =
            Double(promptCacheHitTokens) / 1_000_000 * inputCacheHitUSDPerMillion +
            Double(promptCacheMissTokens) / 1_000_000 * inputCacheMissUSDPerMillion +
            Double(completionTokens) / 1_000_000 * outputUSDPerMillion
        return SmartUsage(
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
            promptTokens: present.reduce(0) { $0 + $1.promptTokens },
            completionTokens: present.reduce(0) { $0 + $1.completionTokens },
            totalTokens: present.reduce(0) { $0 + $1.totalTokens },
            promptCacheHitTokens: present.reduce(0) { $0 + $1.promptCacheHitTokens },
            promptCacheMissTokens: present.reduce(0) { $0 + $1.promptCacheMissTokens },
            estimatedCostUSD: present.reduce(0) { $0 + $1.estimatedCostUSD }
        )
    }
}
