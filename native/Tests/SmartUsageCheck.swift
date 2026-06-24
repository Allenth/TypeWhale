import Foundation

@main
struct SmartUsageCheck {
    static func main() {
        let usage = SmartUsage.deepSeekV4Flash(
            promptTokens: 1_500,
            completionTokens: 500,
            totalTokens: 2_000,
            promptCacheHitTokens: 1_000,
            promptCacheMissTokens: 500
        )
        precondition(usage.totalTokens == 2_000)
        precondition(usage.compactText.contains("2000 tok"))
        precondition(usage.compactText.contains("¥"))
        precondition(!usage.compactText.contains("$"))
        precondition(usage.detailText.contains("输入 1500"))
        precondition(usage.detailText.contains("缓存命中 1000"))
        precondition(usage.detailText.contains("未命中 500"))
        precondition(usage.detailText.contains("输出 500"))
        precondition(usage.detailText.contains("$"))
        precondition(usage.detailText.contains("¥"))
        let hitCost = 1_000.0 / 1_000_000 * 0.0028
        let missCost = 500.0 / 1_000_000 * 0.14
        let outputCost = 500.0 / 1_000_000 * 0.28
        let expected = hitCost + missCost + outputCost
        precondition(abs(usage.estimatedCostUSD - expected) < 0.0000001)
        precondition(abs(usage.estimatedCostCNY - expected * 7.20) < 0.0000001)

        let second = SmartUsage.deepSeekV4Flash(
            promptTokens: 50,
            completionTokens: 25,
            totalTokens: 75,
            promptCacheHitTokens: 10,
            promptCacheMissTokens: 40
        )
        let combined = SmartUsage.combined([usage, nil, second])
        precondition(combined?.promptTokens == 1_550)
        precondition(combined?.completionTokens == 525)
        precondition(combined?.totalTokens == 2_075)
        precondition(combined?.promptCacheHitTokens == 1_010)
        precondition(combined?.promptCacheMissTokens == 540)
        precondition(SmartUsage.combined([nil, nil]) == nil)

        let defaults = UserDefaults.standard
        let localKey = "smartUsageLedger.totalEstimatedCostCNY.v1"
        let baselineKey = "smartUsageLedger.officialBaselineCostCNY.v1"
        let dailyCostKey = "smartUsageLedger.dailyCostCNY.v1"
        let dailyCallKey = "smartUsageLedger.dailyCallCount.v1"
        let dailyTokenKey = "smartUsageLedger.dailyTotalTokens.v1"
        let lastCostKey = "smartUsageLedger.lastCostCNY.v1"
        let lastTokensKey = "smartUsageLedger.lastTotalTokens.v1"
        let lastAtKey = "smartUsageLedger.lastAt.v1"
        let originalLocal = defaults.object(forKey: localKey)
        let originalBaseline = defaults.object(forKey: baselineKey)
        let originalDailyCost = defaults.object(forKey: dailyCostKey)
        let originalDailyCalls = defaults.object(forKey: dailyCallKey)
        let originalDailyTokens = defaults.object(forKey: dailyTokenKey)
        let originalLastCost = defaults.object(forKey: lastCostKey)
        let originalLastTokens = defaults.object(forKey: lastTokensKey)
        let originalLastAt = defaults.object(forKey: lastAtKey)
        defer {
            restore(originalLocal, forKey: localKey)
            restore(originalBaseline, forKey: baselineKey)
            restore(originalDailyCost, forKey: dailyCostKey)
            restore(originalDailyCalls, forKey: dailyCallKey)
            restore(originalDailyTokens, forKey: dailyTokenKey)
            restore(originalLastCost, forKey: lastCostKey)
            restore(originalLastTokens, forKey: lastTokensKey)
            restore(originalLastAt, forKey: lastAtKey)
        }
        defaults.removeObject(forKey: localKey)
        defaults.removeObject(forKey: baselineKey)
        defaults.removeObject(forKey: dailyCostKey)
        defaults.removeObject(forKey: dailyCallKey)
        defaults.removeObject(forKey: dailyTokenKey)
        defaults.removeObject(forKey: lastCostKey)
        defaults.removeObject(forKey: lastTokensKey)
        defaults.removeObject(forKey: lastAtKey)
        SmartUsageLedgerStore.setOfficialBaselineCostCNY(0.66)
        SmartUsageLedgerStore.record(second)
        precondition(abs(SmartUsageLedgerStore.officialBaselineCostCNY - 0.66) < 0.0000001)
        precondition(abs(SmartUsageLedgerStore.locallyRecordedCostCNY - second.estimatedCostCNY) < 0.0000001)
        precondition(abs(SmartUsageLedgerStore.totalEstimatedCostCNY - (0.66 + second.estimatedCostCNY)) < 0.0000001)
        precondition(SmartUsageLedgerStore.todayCallCount == 1)
        precondition(SmartUsageLedgerStore.todayTotalTokens == second.totalTokens)
    }

    private static func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
