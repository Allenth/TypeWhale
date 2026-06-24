import AppKit

@MainActor
final class DeepSeekBalancePopoverViewController: NSViewController {
    private let titleLabel = label("DeepSeek 余额", size: 13, weight: .semibold)
    private let balanceLabel = label("正在查询…", size: 20, weight: .bold)
    private let totalLabel = label("估算总额 --", size: 12, weight: .medium)
    private let spentLabel = label("累计消费（估算） --", size: 12, weight: .medium)
    private let todayYesterdayLabel = label("今天 -- · 昨天 --", size: 12, weight: .medium)
    private let todayUsageLabel = label("今天 0 次 · 0 tok", size: 12, weight: .medium)
    private let lastLabel = label("最近一次 --", size: 12, weight: .medium)
    private let detailLabel = label("今天/昨天/最近一次按本机实时 usage 估算。累计消费 = 官方后台基准 + 实时记录；DeepSeek 接口仅返回实时余额，实际账单以官方为准。", size: 11)
    private let progress = NSProgressIndicator()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 292))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.controlSize = .small
        progress.style = .bar
        progress.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [
            titleLabel,
            balanceLabel,
            progress,
            spentLabel,
            todayYesterdayLabel,
            todayUsageLabel,
            lastLabel,
            totalLabel,
            detailLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    func showLoading() {
        titleLabel.stringValue = "DeepSeek 余额"
        balanceLabel.stringValue = "正在查询…"
        totalLabel.stringValue = "估算总额 --"
        spentLabel.stringValue = "累计消费（估算） \(money(SmartUsageLedgerStore.totalEstimatedCostCNY, currency: "CNY"))"
        refreshLocalStats()
        detailLabel.stringValue = "正在通过 DeepSeek /user/balance 查询实时余额。"
        progress.doubleValue = 0
    }

    func show(balance: DeepSeekBalanceSummary, localSpentCNY: Double) {
        let total = balance.currentBalance + localSpentCNY
        let ratio = total > 0 ? min(max(localSpentCNY / total, 0), 1) : 0
        titleLabel.stringValue = balance.isAvailable ? "DeepSeek 余额可用" : "DeepSeek 余额不可用"
        balanceLabel.stringValue = "实时余额 \(money(balance.currentBalance, currency: balance.currency))"
        totalLabel.stringValue = "估算总额 \(money(total, currency: balance.currency))（实时余额 + 累计消费）"
        spentLabel.stringValue = "累计消费（估算） \(money(localSpentCNY, currency: balance.currency))"
        refreshLocalStats()
        detailLabel.stringValue = "后台基准 \(money(SmartUsageLedgerStore.officialBaselineCostCNY, currency: balance.currency)) · 实时记录 \(money(SmartUsageLedgerStore.locallyRecordedCostCNY, currency: balance.currency))。充值余额 \(money(balance.toppedUpBalance, currency: balance.currency)) · 赠余额 \(money(balance.grantedBalance, currency: balance.currency))。"
        progress.doubleValue = ratio
    }

    func showError(_ message: String) {
        titleLabel.stringValue = "余额查询失败"
        balanceLabel.stringValue = "--"
        totalLabel.stringValue = "估算总额 --"
        spentLabel.stringValue = "累计消费（估算） \(money(SmartUsageLedgerStore.totalEstimatedCostCNY, currency: "CNY"))"
        refreshLocalStats()
        detailLabel.stringValue = message
        progress.doubleValue = 0
    }

    /// 今天/昨天/最近一次都来自本机账本，无需联网即可显示。
    private func refreshLocalStats() {
        todayYesterdayLabel.stringValue = "今天 \(money(SmartUsageLedgerStore.todayCostCNY, currency: "CNY")) · 昨天 \(money(SmartUsageLedgerStore.yesterdayCostCNY, currency: "CNY"))"
        todayUsageLabel.stringValue = "今天 \(SmartUsageLedgerStore.todayCallCount) 次 · \(SmartUsageLedgerStore.todayTotalTokens) tok"
        if SmartUsageLedgerStore.hasLastUsage {
            lastLabel.stringValue = "最近一次 \(money(SmartUsageLedgerStore.lastCostCNY, currency: "CNY")) · \(SmartUsageLedgerStore.lastTotalTokens) tok"
        } else {
            lastLabel.stringValue = "最近一次 暂无记录"
        }
    }

    private func money(_ value: Double, currency: String) -> String {
        let symbol = currency.uppercased() == "CNY" ? "¥" : "\(currency.uppercased()) "
        return String(format: "%@%.4f", symbol, value)
    }
}
