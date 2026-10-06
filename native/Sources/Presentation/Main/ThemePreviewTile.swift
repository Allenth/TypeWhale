import AppKit

/// 主界面「预览主题」列里的一个可点击截图瓦片。
/// 图片只用于主题选择预览；点击行为和主题存储仍由外层控制。
final class ThemePreviewTile: NSView {
    enum Kind {
        case classic
        case notch
        case minimalBlack
    }

    let kind: Kind
    var onSelect: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    private let titleText: String
    private let previewImage: NSImage?
    private let titleHeight: CGFloat = 18

    init(kind: Kind, title: String) {
        self.kind = kind
        self.titleText = title
        previewImage = CapsuleThemeSnapshotFactory.makeSnapshot(for: kind)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 116).isActive = true
        toolTip = "\(title)预览"
        setAccessibilityLabel("\(title)预览")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func draw(_ dirtyRect: NSRect) {
        let sceneRect = NSRect(
            x: 1,
            y: titleHeight,
            width: bounds.width - 2,
            height: bounds.height - titleHeight - 1
        )
        let card = NSBezierPath(roundedRect: sceneRect, xRadius: 8, yRadius: 8)
        UITheme.panelFill.withAlphaComponent(0.70).setFill()
        card.fill()
        card.lineWidth = isSelected ? 2 : 1
        (isSelected ? UITheme.capsuleAccent : UITheme.cardBorder).setStroke()
        card.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        let screen = sceneRect.insetBy(dx: 5, dy: 5)
        let screenPath = NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6)
        UITheme.waterInkBackground.setFill()
        screenPath.fill()
        screenPath.addClip()
        drawPreviewImage(in: screen)
        NSGraphicsContext.current?.restoreGraphicsState()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? UITheme.waterInkAccent : UITheme.waterInkMuted,
        ]
        let titleSize = (titleText as NSString).size(withAttributes: titleAttributes)
        (titleText as NSString).draw(
            at: NSPoint(x: (bounds.width - titleSize.width) / 2, y: 1),
            withAttributes: titleAttributes
        )
    }

    private func drawPreviewImage(in rect: NSRect) {
        guard let previewImage else {
            drawMissingPreview(in: rect)
            return
        }
        let sourceSize = previewImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            drawMissingPreview(in: rect)
            return
        }

        let scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
        let destination = NSRect(
            x: rect.midX - sourceSize.width * scale / 2,
            y: rect.midY - sourceSize.height * scale / 2,
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        previewImage.draw(
            in: destination,
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawMissingPreview(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        ("预览图缺失" as NSString).draw(
            in: NSRect(x: rect.minX, y: rect.midY - 8, width: rect.width, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UITheme.waterInkMuted,
                .paragraphStyle: paragraph,
            ]
        )
    }
}
