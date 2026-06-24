import AppKit

@MainActor
final class DeepSeekBalancePopoverViewController: NSViewController {
    private let titleLabel = label("DeepSeek 余额", size: 13, weight: .semibold)
    private let balanceLabel = label("正在查询…", size: 20, weight: .bold)
    private let totalLabel = label("总金额 --", size: 12, weight: .medium)
    private let spentLabel = label("累计已消费 --", size: 12, weight: .medium)
    private let detailLabel = label("累计已消费 = 官方后台基准 + TypeWhale 后续记录的 usage；DeepSeek 官方接口只返回当前余额。", size: 11)
    private let progress = NSProgressIndicator()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 210))
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
            totalLabel,
            spentLabel,
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
        totalLabel.stringValue = "总金额 --"
        spentLabel.stringValue = "累计已消费 --"
        detailLabel.stringValue = "正在通过 DeepSeek /user/balance 查询当前余额。"
        progress.doubleValue = 0
    }

    func show(balance: DeepSeekBalanceSummary, localSpentCNY: Double) {
        let total = balance.currentBalance + localSpentCNY
        let ratio = total > 0 ? min(max(localSpentCNY / total, 0), 1) : 0
        titleLabel.stringValue = balance.isAvailable ? "DeepSeek 余额可用" : "DeepSeek 余额不可用"
        balanceLabel.stringValue = "余额 \(money(balance.currentBalance, currency: balance.currency))"
        totalLabel.stringValue = "总金额 \(money(total, currency: balance.currency))"
        spentLabel.stringValue = "累计已消费 \(money(localSpentCNY, currency: balance.currency))"
        detailLabel.stringValue = "后台基准 \(money(SmartUsageLedgerStore.officialBaselineCostCNY, currency: balance.currency)) · 后续记录 \(money(SmartUsageLedgerStore.locallyRecordedCostCNY, currency: balance.currency))。充值余额 \(money(balance.toppedUpBalance, currency: balance.currency)) · 赠余额 \(money(balance.grantedBalance, currency: balance.currency))。"
        progress.doubleValue = ratio
    }

    func showError(_ message: String) {
        titleLabel.stringValue = "余额查询失败"
        balanceLabel.stringValue = "--"
        totalLabel.stringValue = "总金额 --"
        spentLabel.stringValue = "累计已消费 \(money(SmartUsageLedgerStore.totalEstimatedCostCNY, currency: "CNY"))"
        detailLabel.stringValue = message
        progress.doubleValue = 0
    }

    private func money(_ value: Double, currency: String) -> String {
        let symbol = currency.uppercased() == "CNY" ? "¥" : "\(currency.uppercased()) "
        return String(format: "%@%.4f", symbol, value)
    }
}
