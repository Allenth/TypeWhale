import Foundation

enum SmartUsageLedgerStore {
    private static let totalEstimatedCostCNYKey = "smartUsageLedger.totalEstimatedCostCNY.v1"
    private static let officialBaselineCostCNYKey = "smartUsageLedger.officialBaselineCostCNY.v1"
    private static let dailyCostCNYKey = "smartUsageLedger.dailyCostCNY.v1"
    private static let dailyCallCountKey = "smartUsageLedger.dailyCallCount.v1"
    private static let dailyTotalTokensKey = "smartUsageLedger.dailyTotalTokens.v1"
    private static let lastCostCNYKey = "smartUsageLedger.lastCostCNY.v1"
    private static let lastTotalTokensKey = "smartUsageLedger.lastTotalTokens.v1"
    private static let lastAtKey = "smartUsageLedger.lastAt.v1"

    /// 本地时区的 yyyy-MM-dd，作为按天账本的键；字典序与时间序一致，便于裁剪旧数据。
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func record(_ usage: SmartUsage?, at date: Date = Date()) {
        guard let usage else { return }
        let cost = usage.estimatedCostCNY

        // 累计（基准日之后的总和）
        let current = UserDefaults.standard.double(forKey: totalEstimatedCostCNYKey)
        UserDefaults.standard.set(current + cost, forKey: totalEstimatedCostCNYKey)

        // 按天
        var daily = dailyCostMap()
        daily[dayKey(for: date), default: 0] += cost
        setDailyCostMap(prune(daily))

        var dailyCalls = dailyIntMap(forKey: dailyCallCountKey)
        dailyCalls[dayKey(for: date), default: 0] += 1
        setDailyIntMap(prune(dailyCalls), forKey: dailyCallCountKey)

        var dailyTokens = dailyIntMap(forKey: dailyTotalTokensKey)
        dailyTokens[dayKey(for: date), default: 0] += usage.totalTokens
        setDailyIntMap(prune(dailyTokens), forKey: dailyTotalTokensKey)

        // 最近一次
        UserDefaults.standard.set(cost, forKey: lastCostCNYKey)
        UserDefaults.standard.set(usage.totalTokens, forKey: lastTotalTokensKey)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastAtKey)
        LaunchDiagnostics.mark("deepseek usage \(usage.requestLogText)")
    }

    static var totalEstimatedCostCNY: Double {
        officialBaselineCostCNY + locallyRecordedCostCNY
    }

    static var locallyRecordedCostCNY: Double {
        UserDefaults.standard.double(forKey: totalEstimatedCostCNYKey)
    }

    static var officialBaselineCostCNY: Double {
        UserDefaults.standard.double(forKey: officialBaselineCostCNYKey)
    }

    static func setOfficialBaselineCostCNY(_ value: Double) {
        UserDefaults.standard.set(max(0, value), forKey: officialBaselineCostCNYKey)
    }

    static var todayCostCNY: Double {
        dailyCostMap()[dayKey(for: Date())] ?? 0
    }

    static var todayCallCount: Int {
        dailyIntMap(forKey: dailyCallCountKey)[dayKey(for: Date())] ?? 0
    }

    static var todayTotalTokens: Int {
        dailyIntMap(forKey: dailyTotalTokensKey)[dayKey(for: Date())] ?? 0
    }

    static var yesterdayCostCNY: Double {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        return dailyCostMap()[dayKey(for: yesterday)] ?? 0
    }

    static var lastCostCNY: Double {
        UserDefaults.standard.double(forKey: lastCostCNYKey)
    }

    static var lastTotalTokens: Int {
        UserDefaults.standard.integer(forKey: lastTotalTokensKey)
    }

    static var hasLastUsage: Bool {
        UserDefaults.standard.object(forKey: lastAtKey) != nil
    }

    // MARK: - 按天存储

    private static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    private static func dailyCostMap() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: dailyCostCNYKey) as? [String: Double] ?? [:]
    }

    private static func setDailyCostMap(_ map: [String: Double]) {
        UserDefaults.standard.set(map, forKey: dailyCostCNYKey)
    }

    private static func dailyIntMap(forKey key: String) -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func setDailyIntMap(_ map: [String: Int], forKey key: String) {
        UserDefaults.standard.set(map, forKey: key)
    }

    /// 只保留最近 keepingDays 天，避免字典无限增长。
    private static func prune(_ map: [String: Double], keepingDays: Int = 60) -> [String: Double] {
        guard map.count > keepingDays,
              let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date())
        else { return map }
        let cutoffKey = dayKey(for: cutoff)
        return map.filter { $0.key >= cutoffKey }
    }

    private static func prune(_ map: [String: Int], keepingDays: Int = 60) -> [String: Int] {
        guard map.count > keepingDays,
              let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date())
        else { return map }
        let cutoffKey = dayKey(for: cutoff)
        return map.filter { $0.key >= cutoffKey }
    }
}
