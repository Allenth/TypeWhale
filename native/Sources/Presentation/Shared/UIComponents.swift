import AppKit

@MainActor
enum UITheme {
    /// 晨雾微光浅色开关：true 时全部色 token 切到浅色版（见 docs/design/concept-c）。
    static var isLight: Bool { AppSettingsStore.useMistLightTheme }
    /// 按当前主题在浅/深两值间取色。深色为现状 water-ink，浅色为晨雾微光。
    private static func themed(_ light: NSColor, _ dark: NSColor) -> NSColor { isLight ? light : dark }

    // Water-ink "灰鲸" palette（深色）/ 晨雾微光（浅色）。左浅右深。
    static var waterInkBackground: NSColor { themed(NSColor(calibratedRed: 0.922, green: 0.937, blue: 0.953, alpha: 1), NSColor(calibratedRed: 0.024, green: 0.043, blue: 0.071, alpha: 1)) }
    static var waterInkSurface: NSColor { themed(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.90), NSColor(calibratedRed: 0.075, green: 0.128, blue: 0.184, alpha: 0.72)) }
    static var waterInkSurfaceStrong: NSColor { themed(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.98), NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.24, alpha: 0.82)) }
    static var waterInkPanel: NSColor { themed(NSColor(calibratedRed: 0.961, green: 0.973, blue: 0.980, alpha: 0.94), NSColor(calibratedRed: 0.072, green: 0.105, blue: 0.145, alpha: 0.72)) }
    static var waterInkPanelLead: NSColor { themed(NSColor(calibratedRed: 0.933, green: 0.953, blue: 0.965, alpha: 0.96), NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.21, alpha: 0.78)) }
    static var waterInkLine: NSColor { themed(NSColor(calibratedRed: 0.251, green: 0.369, blue: 0.455, alpha: 0.15), NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.90, alpha: 0.15)) }
    static var waterInkHairline: NSColor { themed(NSColor(calibratedRed: 0.251, green: 0.369, blue: 0.455, alpha: 0.09), NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.90, alpha: 0.11)) }
    static var waterInkText: NSColor { themed(NSColor(calibratedRed: 0.173, green: 0.243, blue: 0.294, alpha: 1), NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 0.96)) }
    static var waterInkMuted: NSColor { themed(NSColor(calibratedRed: 0.431, green: 0.510, blue: 0.565, alpha: 1), NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.90, alpha: 0.58)) }
    static var waterInkFaint: NSColor { themed(NSColor(calibratedRed: 0.580, green: 0.651, blue: 0.698, alpha: 1), NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.90, alpha: 0.36)) }
    static var waterInkAccent: NSColor { themed(NSColor(calibratedRed: 0.278, green: 0.439, blue: 0.561, alpha: 1), NSColor(calibratedRed: 0.85, green: 0.895, blue: 0.89, alpha: 1)) }
    static var waterInkMistBlue: NSColor { themed(NSColor(calibratedRed: 0.357, green: 0.518, blue: 0.651, alpha: 1), NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.69, alpha: 1)) }
    static var waterInkSuccess: NSColor { themed(NSColor(calibratedRed: 0.353, green: 0.647, blue: 0.533, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.69, alpha: 1)) }
    static var waterInkWarning: NSColor { themed(NSColor(calibratedRed: 0.753, green: 0.592, blue: 0.357, alpha: 1), NSColor(calibratedRed: 0.90, green: 0.78, blue: 0.46, alpha: 1)) }
    /// 录音态 LED（晨雾赭 / 深色暖点）。新增 token。
    static var waterInkRecording: NSColor { themed(NSColor(calibratedRed: 0.816, green: 0.541, blue: 0.447, alpha: 1), NSColor(calibratedRed: 0.88, green: 0.55, blue: 0.45, alpha: 1)) }
    /// 浅色下用一层雾白盖住 HUD 毛玻璃；深色下是原来的深色压暗。
    static var windowOverlay: NSColor { themed(NSColor(calibratedRed: 0.922, green: 0.937, blue: 0.953, alpha: 0.86), NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.075, alpha: 0.72)) }
    static var panelFill: NSColor { waterInkPanel }
    static var panelLeadFill: NSColor { waterInkPanelLead }
    static var capsuleAccent: NSColor { waterInkMistBlue }
    static var capsuleText: NSColor { waterInkText }
    static var waveformStroke: NSColor { themed(NSColor(calibratedRed: 0.478, green: 0.631, blue: 0.761, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.90, blue: 0.94, alpha: 1)) }
    static var waveformGlow: NSColor { themed(NSColor(calibratedRed: 0.478, green: 0.631, blue: 0.761, alpha: 0.6), NSColor(calibratedRed: 0.42, green: 0.70, blue: 0.80, alpha: 1)) }
    nonisolated static let waveformLiveLineWidth: CGFloat = 2.6
    nonisolated static let waveformPreviewLineWidth: CGFloat = 2.4

    static func waveformStrokeColor(activity: CGFloat) -> NSColor {
        waveformStroke.withAlphaComponent(0.82 + 0.18 * Double(activity))
    }

    static func waveformGlowColor(activity: CGFloat) -> NSColor {
        waveformGlow.withAlphaComponent(0.26 + 0.20 * Double(activity))
    }

    // Compatibility aliases kept for existing call sites. 计算属性以随主题切换。
    static var brandYellow: NSColor { waterInkAccent }
    static var brandTint: NSColor { themed(NSColor(calibratedRed: 0.278, green: 0.439, blue: 0.561, alpha: 0.10), NSColor(calibratedRed: 0.85, green: 0.895, blue: 0.89, alpha: 0.09)) }
    static var brandGreen: NSColor { waterInkSuccess }
    static var brandGreenTint: NSColor { themed(NSColor(calibratedRed: 0.353, green: 0.647, blue: 0.533, alpha: 0.12), NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.69, alpha: 0.11)) }
    /// 胶囊「本地服务健康」呼吸边框专用绿：比 brandGreen 更柔和的祖母绿/薄荷绿，
    /// 在深色 HUD 上更耐看，不刺眼。仅用于健康边框，避免影响权限点/刘海脉冲等处的品牌绿。
    static var healthGreen: NSColor { waterInkSuccess }
    /// 录音胶囊毛玻璃背景的圆角半径。RecordingPanel 的圆角裁剪与健康绿环需共用同一值，避免各画各的。
    /// nonisolated：允许在非主线程隔离的静态初始化中直接引用。
    nonisolated static let capsuleCornerRadius: CGFloat = 21
    static var brandTeal: NSColor { brandGreen }
    static var brandTealTint: NSColor { brandGreenTint }
    static var cardFill: NSColor { waterInkPanel }
    static var cardBorder: NSColor { waterInkLine }
    static var hairline: NSColor { waterInkHairline }
    static var sectionTitle: NSColor { waterInkMuted }
    static var keycapFill: NSColor { themed(NSColor(calibratedRed: 0.251, green: 0.369, blue: 0.455, alpha: 0.06), NSColor(calibratedRed: 0.87, green: 0.91, blue: 0.90, alpha: 0.10)) }
    static var keycapBorder: NSColor { themed(NSColor(calibratedRed: 0.251, green: 0.369, blue: 0.455, alpha: 0.16), NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.90, alpha: 0.18)) }
    static var iconTint: NSColor { waterInkMuted }
    static var controlOnFill: NSColor { themed(NSColor(calibratedRed: 0.357, green: 0.518, blue: 0.651, alpha: 0.90), NSColor(calibratedRed: 0.43, green: 0.62, blue: 0.69, alpha: 0.86)) }
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
        .foregroundColor: isSelected ? UITheme.waterInkAccent : UITheme.waterInkMuted,
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
        case .lead: return UITheme.panelLeadFill
        case .standard: return UITheme.cardFill
        }
    }

    var borderColor: NSColor {
        switch self {
        case .lead: return UITheme.cardBorder.withAlphaComponent(0.82)
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
private final class DottedLeaderLineView: NSView {
    private let lineLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        lineLayer.fillColor = nil
        lineLayer.strokeColor = UITheme.hairline.withAlphaComponent(0.72).cgColor
        lineLayer.lineWidth = 1
        lineLayer.lineDashPattern = [1, 3]
        lineLayer.lineCap = .round
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
        lineLayer.path = path
        lineLayer.frame = bounds
        CATransaction.commit()
    }
}

@MainActor
func dottedLeaderView() -> NSView {
    let view = DottedLeaderLineView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.heightAnchor.constraint(equalToConstant: 1).isActive = true
    view.widthAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
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
        (state == .on ? UITheme.controlOnFill : NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.90, alpha: 0.16)).setFill()
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
/// 用振幅门限区分安静/出声，不依赖 Silero VAD，避免 VAD 门控带来的不可用感。
enum WaveformRenderer {
    static let activityFloor: CGFloat = 0.095
    static let activityRange: CGFloat = 1 - activityFloor

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
            let activeBand = max(0, (CGFloat(band) - Self.activityFloor) / Self.activityRange)
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
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = UITheme.waveformLiveLineWidth + 2.6
        UITheme.waveformGlowColor(activity: activity).setStroke()
        path.stroke()
        path.lineWidth = UITheme.waveformLiveLineWidth
        UITheme.waveformStrokeColor(activity: activity).setStroke()
        path.stroke()
    }
}
