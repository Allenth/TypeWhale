import AppKit

@MainActor
enum UITheme {
    // Logo palette: warm golden "sky" (primary) + vivid soft green (secondary accent).
    static let brandYellow = NSColor(calibratedRed: 1.0, green: 0.753, blue: 0.18, alpha: 1)
    static let brandTint = NSColor(calibratedRed: 1.0, green: 0.753, blue: 0.18, alpha: 0.06)
    static let brandGreen = NSColor(calibratedRed: 0.12, green: 0.90, blue: 0.52, alpha: 1)
    static let brandGreenTint = NSColor(calibratedRed: 0.12, green: 0.90, blue: 0.52, alpha: 0.10)
    /// 胶囊「本地服务健康」呼吸边框专用绿：比 brandGreen 更柔和的祖母绿/薄荷绿，
    /// 在深色 HUD 上更耐看，不刺眼。仅用于健康边框，避免影响权限点/刘海脉冲等处的品牌绿。
    static let healthGreen = NSColor(calibratedRed: 0.34, green: 0.84, blue: 0.63, alpha: 1)
    /// 录音胶囊毛玻璃背景的圆角半径。RecordingPanel 的圆角裁剪与健康绿环需共用同一值，避免各画各的。
    /// nonisolated：允许在非主线程隔离的静态初始化（如 HealthBorderOverlayView.Metrics）中直接引用。
    nonisolated static let capsuleCornerRadius: CGFloat = 21
    static let brandTeal = brandGreen
    static let brandTealTint = brandGreenTint
    static let cardFill = NSColor(calibratedWhite: 1, alpha: 0.082)
    static let cardBorder = NSColor(calibratedWhite: 1, alpha: 0.24)
    static let hairline = NSColor(calibratedWhite: 1, alpha: 0.17)
    static let sectionTitle = NSColor(calibratedWhite: 1, alpha: 0.68)
    static let keycapFill = NSColor(calibratedWhite: 1, alpha: 0.13)
    static let keycapBorder = NSColor(calibratedWhite: 1, alpha: 0.24)
    static let iconTint = NSColor(calibratedWhite: 1, alpha: 0.5)
}

/// Shared layout scale so cards, rows and gaps stay on one consistent grid.
@MainActor
enum UILayout {
    static let cornerRadius: CGFloat = 8
    static let rowHeight: CGFloat = 30
    static let compactRowHeight: CGFloat = 26
    static let controlLabelWidth: CGFloat = 160
    static let compactControlLabelWidth: CGFloat = 132
    static let cardPadH: CGFloat = 12
    static let cardPadV: CGFloat = 4
    static let sectionSpacing: CGFloat = 16
    static let groupSpacing: CGFloat = 14
    static let compactGroupSpacing: CGFloat = 10
    static let headerSpacing: CGFloat = 8
}

@MainActor
func sectionHeader(_ text: String) -> NSTextField {
    let value = label(text, size: 12, weight: .medium)
    value.textColor = UITheme.sectionTitle
    return value
}

@MainActor
func panelTitleLabel(_ text: String) -> NSTextField {
    let value = label(text, size: 12, weight: .semibold)
    value.textColor = UITheme.sectionTitle
    value.maximumNumberOfLines = 1
    value.lineBreakMode = .byTruncatingTail
    return value
}

@MainActor
func inspectorGroupTitleLabel(_ text: String) -> NSTextField {
    let value = label(text, size: 11, weight: .semibold)
    value.textColor = UITheme.sectionTitle
    value.maximumNumberOfLines = 1
    value.lineBreakMode = .byTruncatingTail
    return value
}

@MainActor
func controlRowLabel(_ text: String, compact: Bool = false) -> NSTextField {
    let value = label(text, size: 11, weight: .medium)
    value.textColor = compact ? NSColor(calibratedWhite: 1, alpha: 0.72) : NSColor(calibratedWhite: 1, alpha: 0.86)
    value.maximumNumberOfLines = 1
    value.lineBreakMode = .byTruncatingTail
    value.setContentCompressionResistancePriority(.required, for: .horizontal)
    value.widthAnchor.constraint(equalToConstant: compact ? UILayout.compactControlLabelWidth : UILayout.controlLabelWidth).isActive = true
    return value
}

@MainActor
func controlCaptionLabel(_ text: String) -> NSTextField {
    let value = label(text, size: 10, weight: .medium)
    value.textColor = UITheme.sectionTitle
    value.maximumNumberOfLines = 1
    value.lineBreakMode = .byTruncatingTail
    return value
}

@MainActor
func inspectorTabTitleAttributes(isSelected: Bool) -> [NSAttributedString.Key: Any] {
    [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: isSelected ? UITheme.brandYellow : NSColor.secondaryLabelColor,
    ]
}

@MainActor
func inspectorGroupBox(_ content: NSView, prominence: InspectorGroupProminence = .standard) -> NSView {
    let box = roundedBox(content, hPad: 12, vPad: prominence.verticalPadding)
    box.layer?.backgroundColor = prominence.fillColor.cgColor
    box.layer?.borderColor = prominence.borderColor.cgColor
    return box
}

@MainActor
enum InspectorGroupProminence {
    case lead
    case standard

    var verticalPadding: CGFloat {
        switch self {
        case .lead: return 11
        case .standard: return 9
        }
    }

    var fillColor: NSColor {
        switch self {
        case .lead: return NSColor(calibratedWhite: 1, alpha: 0.088)
        case .standard: return UITheme.cardFill
        }
    }

    var borderColor: NSColor {
        switch self {
        case .lead: return NSColor(calibratedWhite: 1, alpha: 0.28)
        case .standard: return UITheme.cardBorder
        }
    }
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
    box.layer?.cornerRadius = UILayout.cornerRadius
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
func listCard(_ rows: [NSView], hPad: CGFloat = 15, vPad: CGFloat = 3) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    for (index, row) in rows.enumerated() {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if index < rows.count - 1 {
            let separator = hairlineView()
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    return roundedBox(stack, hPad: hPad, vPad: vPad)
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

/// 共享的波形频段状态：非对称平滑（起声快、收声慢）。胶囊与主窗口共用同一份，避免两处各写一遍。
struct WaveformBands {
    private(set) var values: [Float]
    private let baseline: Float
    private let attack: Float
    private let release: Float

    init(count: Int = 7, baseline: Float = 0.08, attack: Float = 0.52, release: Float = 0.16) {
        self.values = Array(repeating: baseline, count: count)
        self.baseline = baseline
        self.attack = attack
        self.release = release
    }

    mutating func apply(_ newBands: [Float]) {
        for index in values.indices {
            let target = index < newBands.count ? newBands[index] : baseline
            let smoothing = target > values[index] ? attack : release
            values[index] += (target - values[index]) * smoothing
        }
    }

    mutating func reset() {
        for index in values.indices { values[index] = baseline }
    }
}

/// 1.4 验证过的折线机制：一条水平折线，静音（振幅低于门限）时保持平直，
/// 有人声时整条线一起按声纹强度上下波动。直线段连接，两端钉在中线。
/// 用振幅门限（0.16）区分安静/出声，不依赖 Silero VAD，避免 VAD 门控带来的不可用感。
enum WaveformRenderer {
    /// 把频段映射成折线路径，并返回峰值活跃度（0...1）供调用方调节颜色。
    static func makePath(bands: [Float], in rect: NSRect) -> (path: NSBezierPath, activity: CGFloat) {
        let count = bands.count
        guard count > 1 else { return (NSBezierPath(), 0) }
        let midY = rect.midY
        let maxAmplitude = rect.height / 2 - 1
        let half = CGFloat(count - 1) / 2
        var peakActivity: CGFloat = 0

        var points: [NSPoint] = [NSPoint(x: rect.minX, y: midY)]
        for (index, band) in bands.enumerated() {
            let centerDistance = abs(CGFloat(index) - half) / half
            // 各点权重接近一致，说话时整条线一起波动；门限保证安静时是一条平直线。
            let centerWeight = 0.86 + (1 - centerDistance) * 0.22
            let activeBand = max(0, (CGFloat(band) - 0.16) / 0.84)
            peakActivity = max(peakActivity, activeBand)
            let emphasized = activeBand <= 0 ? 0 : pow(activeBand, 0.62)
            let direction: CGFloat = index % 2 == 0 ? 1 : -1
            let offset = emphasized * centerWeight * maxAmplitude * direction
            let x = rect.minX + rect.width * (CGFloat(index) + 0.5) / CGFloat(count)
            points.append(NSPoint(x: x, y: midY + offset))
        }
        points.append(NSPoint(x: rect.maxX, y: midY))

        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        return (path, min(1, peakActivity))
    }
}

final class MiniWaveformView: NSView {
    private var bands = WaveformBands(attack: 0.62, release: 0.22)

    override var isOpaque: Bool { false }

    func update(_ newBands: [Float]) {
        bands.apply(newBands)
        needsDisplay = true
    }

    func reset() {
        bands.reset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // 与录音胶囊统一：静音平直、出声时整条线上下波动（详见 WaveformRenderer，1.4 折线机制）。
        let (path, activity) = WaveformRenderer.makePath(bands: bands.values, in: bounds)
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UITheme.brandGreen.withAlphaComponent(0.5 + 0.5 * Double(activity)).setStroke()
        path.stroke()
    }
}
