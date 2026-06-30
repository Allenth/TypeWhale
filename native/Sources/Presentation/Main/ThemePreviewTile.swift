import AppKit

/// 主界面「预览主题」列里的一个可点击预览瓦片：程序绘制对应主题的迷你示意图 + 标题。
/// 点击触发 `onSelect` 切换主题；选中态用品牌色边框高亮。
final class ThemePreviewTile: NSView {
    enum Kind { case classic, notch }

    let kind: Kind
    var onSelect: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    private let titleText: String
    private let titleHeight: CGFloat = 18

    init(kind: Kind, title: String) {
        self.kind = kind
        self.titleText = title
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 98).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func draw(_ dirtyRect: NSRect) {
        let sceneRect = NSRect(x: 1, y: titleHeight, width: bounds.width - 2, height: bounds.height - titleHeight - 1)
        let card = NSBezierPath(roundedRect: sceneRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 1, alpha: 0.05).setFill()
        card.fill()
        card.lineWidth = isSelected ? 2 : 1
        (isSelected ? UITheme.brandTeal : UITheme.cardBorder).setStroke()
        card.stroke()

        // 模拟一个屏幕画面（裁剪范围只作用于场景，不影响标题）。
        NSGraphicsContext.current?.saveGraphicsState()
        let screen = sceneRect.insetBy(dx: 12, dy: 12)
        let screenPath = NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6)
        NSColor(calibratedWhite: 1, alpha: 0.05).setFill()
        screenPath.fill()
        screenPath.addClip()
        switch kind {
        case .classic: drawClassic(in: screen)
        case .notch: drawNotch(in: screen)
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // 标题。
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? UITheme.brandTeal : NSColor.secondaryLabelColor,
        ]
        let size = (titleText as NSString).size(withAttributes: attrs)
        (titleText as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: 1),
            withAttributes: attrs
        )
    }

    /// 默认主题：底部居中胶囊 + teal 波形线。
    private func drawClassic(in screen: NSRect) {
        let pillW = screen.width * 0.64
        let pillH: CGFloat = 13
        let pill = NSRect(x: screen.midX - pillW / 2, y: screen.minY + 9, width: pillW, height: pillH)
        NSColor(calibratedWhite: 0.1, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()

        let mid = pill.midY
        let line = NSBezierPath()
        line.move(to: NSPoint(x: pill.minX + 7, y: mid))
        let n = 6
        for i in 1...n {
            let x = pill.minX + 7 + (pill.width - 14) * CGFloat(i) / CGFloat(n)
            line.line(to: NSPoint(x: x, y: mid + (i % 2 == 0 ? 3 : -3)))
        }
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        UITheme.brandTeal.setStroke()
        line.stroke()
    }

    /// 刘海主题：状态栏下方居中的圆角黑岛（灵动岛）+ 左图标点/右脉冲点 + 文字条。
    private func drawNotch(in screen: NSRect) {
        let islandW = screen.width * 0.56
        let islandH: CGFloat = 15
        let island = NSRect(x: screen.midX - islandW / 2, y: screen.maxY - islandH - 7, width: islandW, height: islandH)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: island, xRadius: islandH / 2, yRadius: islandH / 2).fill()

        let dotR: CGFloat = 2.3
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: island.minX + 5, y: island.midY - dotR, width: dotR * 2, height: dotR * 2)).fill()
        UITheme.brandTeal.setFill()
        NSBezierPath(ovalIn: NSRect(x: island.maxX - 5 - dotR * 2, y: island.midY - dotR, width: dotR * 2, height: dotR * 2)).fill()

        let bar = NSRect(x: island.midX - islandW * 0.16, y: island.midY - 1.5, width: islandW * 0.32, height: 3)
        NSColor(calibratedWhite: 1, alpha: 0.5).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
