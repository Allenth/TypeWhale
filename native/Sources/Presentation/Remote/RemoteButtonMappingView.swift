import AppKit

@MainActor
final class RemoteButtonMappingView: NSView {
    var onMappingChange: ((RemoteButton, RemoteButtonAction) -> Void)?
    var onResetMappings: (() -> Void)?
    var onButtonPreview: ((RemoteButton) -> Void)?

    private let resetMappingsButton = NSButton(title: "恢复默认", target: nil, action: nil)
    private var mappingPopups: [RemoteButton: NSPopUpButton] = [:]
    private var mappingButtons: [Int: RemoteButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        resetMappingsButton.target = self
        resetMappingsButton.action = #selector(resetMappings(_:))
        resetMappingsButton.bezelStyle = .inline
        resetMappingsButton.controlSize = .small
        resetMappingsButton.setAccessibilityLabel("恢复默认按键映射")
        let group = RemoteInspectorSectionFactory.group(title: "按键映射", body: makeMappings())
        RemoteInspectorSectionFactory.pin(group, to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(mapping: RemoteButtonMapping) {
        for (button, popup) in mappingPopups {
            let rawValue = mapping.binding(for: button).actionID.rawValue
            if let item = popup.itemArray.first(where: { $0.representedObject as? String == rawValue }) {
                popup.select(item)
            }
        }
    }

    private func makeMappings() -> NSView {
        let resetRow = NSStackView(views: [
            label("13 个物理按键均可自定义", size: 10),
            flexSpacer(),
            resetMappingsButton,
        ])
        resetRow.orientation = .horizontal
        resetRow.alignment = .centerY

        var rows: [NSView] = [resetRow, hairlineView()]
        let editableButtons = RemoteButtonPresentation.editableButtons(
            supportedButtons: XiaomiRemote2ProHIDProfile.supportedButtons
        )
        let midpoint = (editableButtons.count + 1) / 2
        let leftColumn = mappingColumn(
            buttons: Array(editableButtons[..<midpoint]),
            startingTag: 0
        )
        let rightColumn = mappingColumn(
            buttons: Array(editableButtons[midpoint...]),
            startingTag: midpoint
        )
        let columns = NSStackView(views: [leftColumn, rightColumn])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 14
        rows.append(columns)
        let note = label("保留默认值；自定义动作会替换该键的系统原动作。", size: 10)
        note.textColor = UITheme.waterInkFaint
        rows.append(note)
        let stack = RemoteInspectorSectionFactory.vertical(rows, spacing: 5)
        resetRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        columns.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func mappingColumn(buttons: [RemoteButton], startingTag: Int) -> NSStackView {
        let rows = buttons.enumerated().map { offset, button in
            editableMappingRow(button: button, tag: startingTag + offset)
        }
        return RemoteInspectorSectionFactory.vertical(rows, spacing: 5)
    }

    private func editableMappingRow(button: RemoteButton, tag: Int) -> NSView {
        let popup = RemoteButtonPreviewPopUpButton(button: button)
        popup.controlSize = .small
        popup.target = self
        popup.action = #selector(changeMapping(_:))
        popup.onPreview = { [weak self] button in
            self?.onButtonPreview?(button)
        }
        popup.tag = tag
        mappingButtons[tag] = button
        for (index, group) in RemoteButtonActionPresentation.groups(for: button).enumerated() {
            if index > 0 {
                popup.menu?.addItem(.separator())
            }
            let heading = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            popup.menu?.addItem(heading)
            for action in group.actions {
                popup.addItem(withTitle: RemoteButtonPresentation.actionTitle(for: action))
                popup.lastItem?.representedObject = RemoteActionCatalog.builtIn
                    .descriptor(for: action)?
                    .id.rawValue
            }
        }
        popup.widthAnchor.constraint(equalToConstant: 142).isActive = true
        popup.setAccessibilityLabel("\(RemoteButtonPresentation.title(for: button))动作")
        mappingPopups[button] = popup
        let row = NSStackView(views: [
            compactButtonLabel(RemoteButtonPresentation.title(for: button)),
            popup,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: UILayout.compactRowHeight).isActive = true
        return row
    }

    private func compactButtonLabel(_ text: String) -> NSTextField {
        let value = label(text, size: 10, weight: .medium)
        value.textColor = UITheme.waterInkMuted
        value.maximumNumberOfLines = 1
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        return value
    }

    @objc private func changeMapping(_ sender: NSPopUpButton) {
        guard let button = mappingButtons[sender.tag],
              let rawValue = sender.selectedItem?.representedObject as? String,
              let action = RemoteActionCatalog.builtIn
                .descriptor(for: RemoteActionID(rawValue: rawValue))?
                .legacyAction else { return }
        onButtonPreview?(button)
        onMappingChange?(button, action)
    }

    @objc private func resetMappings(_ sender: NSButton) {
        onResetMappings?()
    }
}
