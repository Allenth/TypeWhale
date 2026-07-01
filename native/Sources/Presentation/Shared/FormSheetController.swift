import AppKit

/// 通用表单 sheet：替代把编辑器塞进 NSAlert 的旧做法。
///
/// 顶部标题 + 说明，中间放调用方提供的自定义内容视图，底部右对齐按钮行；
/// 以原生 sheet 形式挂在父窗口标题栏下滑出，非「警告框」观感。
/// 呈现期间自持有，直到某个按钮结束 sheet 后释放。
final class FormSheetController: NSObject {
    struct ButtonSpec {
        let title: String
        var isDefault: Bool = false
        var isCancel: Bool = false
    }

    private var sheetWindow: NSWindow?
    private var completion: ((Int) -> Void)?
    private var retain: FormSheetController?

    /// 在 `parent` 下以 sheet 呈现，`completion` 回传被点击按钮的下标（与 `buttons` 顺序一致）。
    func present(
        in parent: NSWindow,
        title: String,
        message: String,
        contentView: NSView,
        contentSize: NSSize,
        buttons: [ButtonSpec],
        completion: @escaping (Int) -> Void
    ) {
        self.completion = completion
        self.retain = self

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = contentSize.width

        contentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, messageLabel, contentView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, spec) in buttons.enumerated() {
            let button = NSButton(title: spec.title, target: self, action: #selector(buttonTapped(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            if spec.isDefault { button.keyEquivalent = "\r" }
            if spec.isCancel { button.keyEquivalent = "\u{1b}" }
            buttonRow.addArrangedSubview(button)
        }

        let root = NSView()
        root.addSubview(stack)
        root.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            contentView.widthAnchor.constraint(equalToConstant: contentSize.width),
            contentView.heightAnchor.constraint(equalToConstant: contentSize.height),
            buttonRow.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width + 40, height: contentSize.height + 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)

        sheetWindow = window
        parent.beginSheet(window) { _ in }
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        finish(with: sender.tag)
    }

    private func finish(with index: Int) {
        if let window = sheetWindow, let parent = window.sheetParent {
            parent.endSheet(window)
        }
        let done = completion
        completion = nil
        sheetWindow = nil
        done?(index)
        retain = nil
    }
}
