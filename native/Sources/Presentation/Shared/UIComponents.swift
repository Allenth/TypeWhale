import AppKit

@MainActor
enum UITheme {
    static let brandYellow = NSColor(calibratedRed: 1.0, green: 0.753, blue: 0.18, alpha: 1)
    static let brandTint = NSColor(calibratedRed: 1.0, green: 0.753, blue: 0.18, alpha: 0.06)
    static let cardFill = NSColor(calibratedWhite: 1, alpha: 0.06)
    static let cardBorder = NSColor(calibratedWhite: 1, alpha: 0.12)
    static let hairline = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let sectionTitle = NSColor(calibratedWhite: 1, alpha: 0.42)
    static let keycapFill = NSColor(calibratedWhite: 1, alpha: 0.10)
    static let keycapBorder = NSColor(calibratedWhite: 1, alpha: 0.16)
    static let iconTint = NSColor(calibratedWhite: 1, alpha: 0.5)
}

@MainActor
func sectionHeader(_ text: String) -> NSTextField {
    let value = label(text, size: 12, weight: .medium)
    value.textColor = UITheme.sectionTitle
    return value
}

@MainActor
func flexSpacer() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}

@MainActor
func hairlineView() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = UITheme.hairline.cgColor
    view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    return view
}

@MainActor
func symbolIcon(_ name: String, size: CGFloat = 16, color: NSColor = NSColor(calibratedWhite: 1, alpha: 0.5)) -> NSImageView {
    let imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    imageView.contentTintColor = color
    imageView.imageScaling = .scaleProportionallyDown
    imageView.widthAnchor.constraint(equalToConstant: 20).isActive = true
    return imageView
}

/// A rounded translucent surface that wraps a single content view.
@MainActor
func roundedBox(_ content: NSView, hPad: CGFloat = 15, vPad: CGFloat = 14) -> NSView {
    let box = NSView()
    box.translatesAutoresizingMaskIntoConstraints = false
    box.wantsLayer = true
    box.layer?.backgroundColor = UITheme.cardFill.cgColor
    box.layer?.cornerRadius = 12
    box.layer?.borderWidth = 0.5
    box.layer?.borderColor = UITheme.cardBorder.cgColor
    content.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: hPad),
        content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -hPad),
        content.topAnchor.constraint(equalTo: box.topAnchor, constant: vPad),
        content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -vPad),
    ])
    return box
}

/// A rounded surface containing a vertical list of rows, with hairline separators between them.
@MainActor
func listCard(_ rows: [NSView], hPad: CGFloat = 15) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    for (index, row) in rows.enumerated() {
        stack.addArrangedSubview(row)
        if index < rows.count - 1 {
            stack.addArrangedSubview(hairlineView())
        }
    }
    return roundedBox(stack, hPad: hPad, vPad: 3)
}

/// A keycap-styled wrapper around a label, used to display hotkeys.
final class KeycapView: NSView {
    let textField: NSTextField

    init(_ field: NSTextField, minWidth: CGFloat = 40, height: CGFloat = 30) {
        textField = field
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = UITheme.keycapFill.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = UITheme.keycapBorder.cgColor

        field.translatesAutoresizingMaskIntoConstraints = false
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A self-drawn toggle styled in the brand color (NSSwitch can't be tinted).
/// Behaves like NSButton: exposes `state` (.on/.off) and fires its action on click.
final class BrandSwitch: NSButton {
    private let trackWidth: CGFloat = 38
    private let trackHeight: CGFloat = 22

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        setButtonType(.toggle)
        isBordered = false
        title = ""
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: trackWidth, height: trackHeight) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(
            x: (bounds.width - trackWidth) / 2,
            y: (bounds.height - trackHeight) / 2,
            width: trackWidth,
            height: trackHeight
        )
        let radius = trackHeight / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (state == .on ? UITheme.brandYellow : NSColor(calibratedWhite: 1, alpha: 0.16)).setFill()
        track.fill()

        let inset: CGFloat = 2
        let diameter = trackHeight - inset * 2
        let knobX = state == .on ? rect.maxX - diameter - inset : rect.minX + inset
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: rect.minY + inset, width: diameter, height: diameter)).fill()
    }
}

/// A compact 7-band waveform that echoes the recording capsule, shown in the main window's status panel.
final class MiniWaveformView: NSView {
    private var bands = Array(repeating: Float(0.10), count: 7)

    override var isOpaque: Bool { false }

    func update(_ newBands: [Float]) {
        for index in bands.indices {
            let target = index < newBands.count ? newBands[index] : 0.08
            let smoothing: Float = target > bands[index] ? 0.62 : 0.22
            bands[index] += (target - bands[index]) * smoothing
        }
        needsDisplay = true
    }

    func reset() {
        bands = Array(repeating: Float(0.10), count: bands.count)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 4
        let spacing: CGFloat = 12
        let count = bands.count
        let total = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        var x = (bounds.width - total) / 2
        for (index, band) in bands.enumerated() {
            let centerDistance = abs(CGFloat(index) - 3) / 3
            let centerWeight = 0.55 + (1 - centerDistance) * 0.60
            let activeBand = max(0, (CGFloat(band) - 0.08) / 0.92)
            let emphasized = pow(activeBand, 0.32)
            let height = max(3, min(bounds.height, bounds.height * (0.08 + emphasized * centerWeight * 1.05)))
            UITheme.brandYellow.withAlphaComponent(0.45 + 0.55 * min(1, Double(activeBand))).setFill()
            let bar = NSBezierPath(
                roundedRect: NSRect(x: x, y: (bounds.height - height) / 2, width: barWidth, height: height),
                xRadius: 2,
                yRadius: 2
            )
            bar.fill()
            x += barWidth + spacing
        }
    }
}
