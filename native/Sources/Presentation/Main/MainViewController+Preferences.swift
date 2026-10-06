import AppKit

extension MainViewController {
    @objc func openPreferences() {
        selectInspectorTab(.common)
    }

    func section(_ title: String, _ card: NSView) -> NSView {
        let stack = NSStackView(views: [sectionHeader(title), card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.headerSpacing
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func shortcutRow(
        title: String,
        captureButton: NSButton,
        fallbackButton: NSButton,
        mousePresetPicker: NSPopUpButton?
    ) -> NSView {
        let titleLabel = controlRowLabel(title)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        fallbackButton.translatesAutoresizingMaskIntoConstraints = false
        let rowViews: [NSView] = {
            guard let popup = mousePresetPicker else { return [titleLabel, flexSpacer(), captureButton, fallbackButton] }
            popup.translatesAutoresizingMaskIntoConstraints = false
            return [titleLabel, popup, captureButton, fallbackButton]
        }()

        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func optionRow(_ title: String, _ control: NSView, showsLeader: Bool = false) -> NSView {
        let titleLabel = controlRowLabel(title)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let middle = showsLeader ? dottedLeaderView() : flexSpacer()
        let row = NSStackView(views: [titleLabel, middle, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func compactOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = controlRowLabel(title, compact: true)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: UILayout.compactRowHeight).isActive = true
        return row
    }

    func stackedOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = controlRowLabel(title)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true
        row.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return row
    }
}
