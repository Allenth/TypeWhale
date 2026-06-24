import Foundation

enum SmartUsageLedgerStore {
    private static let totalEstimatedCostCNYKey = "smartUsageLedger.totalEstimatedCostCNY.v1"
    private static let officialBaselineCostCNYKey = "smartUsageLedger.officialBaselineCostCNY.v1"

    static func record(_ usage: SmartUsage?) {
        guard let usage else { return }
        let current = UserDefaults.standard.double(forKey: totalEstimatedCostCNYKey)
        UserDefaults.standard.set(current + usage.estimatedCostCNY, forKey: totalEstimatedCostCNYKey)
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
}
