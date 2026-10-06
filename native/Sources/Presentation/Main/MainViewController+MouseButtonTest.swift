import AppKit

final class MouseButtonTestViewController: NSViewController {
    var onClose: (() -> Void)?

    private let titleLabel = label("鼠标侧键测试", size: 14, weight: .semibold)
    private let hintLabel = label(
        "显示每个物理鼠标键的系统按钮号，以及 TypeWhale 会把它当作第几键。",
        size: 11
    )
    private let statusLabel = label("等待识别...", size: 11, weight: .medium)
    private let detailLabel = label("", size: 11)
    private let buttonHelpLabel = label(
        "清空结果：清除上方识别文字；关闭：退出测试并恢复鼠标快捷键。",
        size: 10
    )
    private let resetButton = NSButton(title: "清空结果", target: nil, action: nil)
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)

    override func loadView() {
        let statusContainer = NSStackView(views: [statusLabel, detailLabel])
        statusContainer.orientation = .vertical
        statusContainer.alignment = .leading
        statusContainer.spacing = 4

        let buttonRow = NSStackView(views: [resetButton, flexSpacer(), closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        titleLabel.textColor = UITheme.sectionTitle
        hintLabel.textColor = UITheme.waterInkMuted
        hintLabel.maximumNumberOfLines = 0
        statusLabel.textColor = NSColor.textColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        detailLabel.textColor = UITheme.waterInkMuted
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping
        buttonHelpLabel.textColor = UITheme.waterInkMuted
        buttonHelpLabel.maximumNumberOfLines = 0
        buttonHelpLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [titleLabel, hintLabel, hairlineView(), statusContainer, buttonHelpLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12),
        ])

        resetButton.target = self
        resetButton.action = #selector(clearResult)
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.font = .systemFont(ofSize: 11, weight: .medium)
        resetButton.toolTip = "只清除本测试窗口里的识别结果，不修改任何快捷键设置。"

        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.font = .systemFont(ofSize: 11, weight: .medium)
        closeButton.toolTip = "关闭鼠标键测试，并恢复 TypeWhale 的鼠标快捷键监听。"

        view = root
    }

    func setStatus(_ status: String, detail: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = status
            self?.detailLabel.stringValue = detail
        }
    }

    func reset() {
        setStatus("等待识别...", detail: "这个测试只旁听鼠标事件，不会拦截系统快捷功能。")
    }

    @objc private func clearResult() {
        reset()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
