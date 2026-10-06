import AppKit

final class ShadowPreviewView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let badgeX: CGFloat = 10
        static let badgeWidth: CGFloat = 40
        static let textX: CGFloat = 58
        static let trailingInset: CGFloat = 14
    }

    private var state: PreviewViewState?

    override var isFlipped: Bool { true }

    func apply(_ state: PreviewViewState) {
        self.state = state
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        NSColor(calibratedWhite: 0.055, alpha: 0.91).setFill()
        background.fill()
        NSColor(calibratedRed: 0.42, green: 0.64, blue: 0.72, alpha: 0.42).setStroke()
        background.lineWidth = 1
        background.stroke()

        drawBadge()
        drawTranscript()
    }

    private func drawBadge() {
        let badgeRect = NSRect(
            x: Metrics.badgeX,
            y: (bounds.height - 18) / 2,
            width: Metrics.badgeWidth,
            height: 18
        )
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7)
        NSColor(calibratedRed: 0.25, green: 0.46, blue: 0.54, alpha: 0.5).setFill()
        badge.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        ("旁路" as NSString).draw(
            in: badgeRect.offsetBy(dx: 0, dy: 2),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.9),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawTranscript() {
        let textRect = NSRect(
            x: Metrics.textX,
            y: 0,
            width: max(0, bounds.width - Metrics.textX - Metrics.trailingInset),
            height: bounds.height
        )
        let stable = state?.stableWindowText ?? "等待旁路结果…"
        let volatile = state?.volatileTailText ?? ""
        let display: String
        if state?.failure != nil {
            display = "旁路暂不可用"
        } else {
            display = stable + volatile
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.alignment = .left
        let value = NSMutableAttributedString(
            string: display,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.94),
                .paragraphStyle: paragraph
            ]
        )
        if state?.failure == nil, !volatile.isEmpty {
            let volatileCount = min(volatile.count, value.length)
            let volatileRange = NSRange(location: value.length - volatileCount, length: volatileCount)
            value.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 0.52)
                ],
                range: volatileRange
            )
        }
        value.draw(
            with: textRect.insetBy(dx: 0, dy: 11),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}
