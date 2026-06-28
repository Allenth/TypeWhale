import AppKit

extension MainViewController {
    @objc func openPreferences() {
        scrollToConfigPanels()
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
        fallbackButton: NSButton
    ) -> NSView {
        let titleLabel = label(title, size: 12)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, flexSpacer(), captureButton, fallbackButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func optionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 12)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func compactOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 10, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.72)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }

    func stackedOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
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
