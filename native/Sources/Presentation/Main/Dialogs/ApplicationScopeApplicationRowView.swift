import AppKit

@MainActor
final class ApplicationScopeApplicationRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let bundleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func render(
        item: ApplicationCatalogItem,
        icon: NSImage,
        isSelected: Bool,
        valueText: String
    ) {
        iconView.image = icon
        nameLabel.stringValue = item.displayName
        bundleLabel.stringValue = item.bundleIdentifier
        valueLabel.stringValue = valueText
        valueLabel.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
    }

    private func configure() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        bundleLabel.font = .systemFont(ofSize: 10)
        bundleLabel.textColor = .tertiaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.font = .systemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [nameLabel, bundleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labels)
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -8),

            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
    }
}
