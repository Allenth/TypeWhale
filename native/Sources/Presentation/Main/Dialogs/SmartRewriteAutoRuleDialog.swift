import AppKit

@MainActor
final class SmartRewriteAutoRuleDialog: NSObject {
    enum Result {
        case save(SmartRewriteAutoConfiguration)
        case reset
        case cancel
    }

    @MainActor
    private final class RuleRow {
        let id: String
        let enabledButton: NSButton
        let titleField: NSTextField
        let keywordField: NSTextField
        let modePicker: NSPopUpButton

        init(rule: SmartRewriteAutoRule) {
            id = rule.id
            enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            enabledButton.state = rule.isEnabled ? .on : .off

            titleField = NSTextField(string: rule.title)
            titleField.font = .systemFont(ofSize: 12, weight: .medium)
            titleField.isBordered = true
            titleField.bezelStyle = .roundedBezel
            titleField.lineBreakMode = .byTruncatingTail

            keywordField = NSTextField(string: rule.keywordText)
            keywordField.font = .systemFont(ofSize: 12)
            keywordField.placeholderString = "窗口名、App 名或 Bundle ID，逗号分隔"
            keywordField.isBordered = true
            keywordField.bezelStyle = .roundedBezel
            keywordField.lineBreakMode = .byTruncatingMiddle

            modePicker = NSPopUpButton()
            Self.populate(modePicker, selected: rule.mode)
        }

        var rule: SmartRewriteAutoRule {
            var value = SmartRewriteAutoRule(
                id: id,
                title: titleField.stringValue,
                keywords: [],
                mode: Self.selectedMode(from: modePicker),
                isEnabled: enabledButton.state == .on
            )
            value.keywordText = keywordField.stringValue
            return value
        }

        static func populate(_ picker: NSPopUpButton, selected: RewriteMode) {
            picker.removeAllItems()
            for mode in SmartRewriteAutoRuleStore.selectableModes {
                picker.addItem(withTitle: mode.displayName)
                picker.lastItem?.representedObject = mode.rawValue
            }
            picker.selectItem(withTitle: selected.displayName)
            picker.bezelStyle = .rounded
            picker.controlSize = .regular
            picker.font = .systemFont(ofSize: 12)
        }

        static func selectedMode(from picker: NSPopUpButton) -> RewriteMode {
            guard let rawValue = picker.selectedItem?.representedObject as? String,
                  let mode = RewriteMode(rawValue: rawValue) else {
                return .polish
            }
            return mode
        }
    }

    private var configuration: SmartRewriteAutoConfiguration
    private var rows: [RuleRow] = []
    private let fallbackPicker = NSPopUpButton()

    init(configuration: SmartRewriteAutoConfiguration) {
        self.configuration = configuration
        super.init()
    }

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "自动模式范围"
        alert.informativeText = "为常用窗口设置自动使用的智能整理模式。匹配内容来自目标 App 名、Bundle ID 和窗口标题。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(SmartRewriteAutoConfiguration(
                rules: rows.map(\.rule),
                fallbackMode: RuleRow.selectedMode(from: fallbackPicker)
            ))
        case .alertSecondButtonReturn:
            return .reset
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        rows = configuration.rules.map(RuleRow.init(rule:))
        RuleRow.populate(fallbackPicker, selected: configuration.fallbackMode)

        let header = buildHeaderRow()
        let ruleRows = rows.map(buildRuleRow)

        let fallbackLabel = NSTextField(labelWithString: "未匹配时")
        fallbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let fallbackHint = NSTextField(labelWithString: "没有命中任何范围时使用的整理模式")
        fallbackHint.font = .systemFont(ofSize: 11)
        fallbackHint.textColor = .secondaryLabelColor
        let fallbackText = NSStackView(views: [fallbackLabel, fallbackHint])
        fallbackText.orientation = .vertical
        fallbackText.alignment = .leading
        fallbackText.spacing = 2
        let fallbackRow = NSStackView(views: [fallbackText, flexSpacer(), fallbackPicker])
        fallbackRow.orientation = .horizontal
        fallbackRow.alignment = .centerY
        fallbackRow.spacing = 10

        let hint = NSTextField(labelWithString: "提示：关键词支持 App 名、窗口标题、Bundle ID 片段，例如 codex、com.openai.chat、xcode。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [header] + ruleRows + [hairlineView(), fallbackRow, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 286))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            fallbackRow.widthAnchor.constraint(equalToConstant: 560),
            fallbackPicker.widthAnchor.constraint(equalToConstant: 116),
            hint.widthAnchor.constraint(equalToConstant: 560),
        ])
        return container
    }

    private func buildHeaderRow() -> NSView {
        let enabled = headerLabel("启用")
        let title = headerLabel("范围")
        let keywords = headerLabel("匹配关键词")
        let mode = headerLabel("模式")
        let row = NSStackView(views: [enabled, title, keywords, mode])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        NSLayoutConstraint.activate([
            enabled.widthAnchor.constraint(equalToConstant: 34),
            title.widthAnchor.constraint(equalToConstant: 118),
            keywords.widthAnchor.constraint(equalToConstant: 266),
            mode.widthAnchor.constraint(equalToConstant: 116),
        ])
        return row
    }

    private func buildRuleRow(_ rowModel: RuleRow) -> NSView {
        let row = NSStackView(views: [
            rowModel.enabledButton,
            rowModel.titleField,
            rowModel.keywordField,
            rowModel.modePicker,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        NSLayoutConstraint.activate([
            rowModel.enabledButton.widthAnchor.constraint(equalToConstant: 34),
            rowModel.titleField.widthAnchor.constraint(equalToConstant: 118),
            rowModel.keywordField.widthAnchor.constraint(equalToConstant: 266),
            rowModel.modePicker.widthAnchor.constraint(equalToConstant: 116),
            row.heightAnchor.constraint(equalToConstant: 30),
        ])
        return row
    }

    private func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }
}

