import AppKit

final class MinimalBlackPreviewView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let horizontalInset: CGFloat = 14
        static let waveformWidth: CGFloat = 72
    }

    private var renderState = MinimalBlackRenderState.empty
    private var statusText = "录音中"
    private var bands = Array(repeating: Float.zero, count: 7)
    private var inputLevel: CGFloat = 0
    private var memoryHigh = false

    override var isFlipped: Bool { true }

    func apply(_ renderState: MinimalBlackRenderState) {
        guard self.renderState != renderState else { return }
        self.renderState = renderState
        needsDisplay = true
    }

    func updateStatus(_ status: String) {
        guard statusText != status else { return }
        statusText = status
        needsDisplay = true
    }

    func updateBands(_ bands: [Float]) {
        self.bands = bands.isEmpty ? Array(repeating: 0, count: 7) : bands
        needsDisplay = true
    }

    func updateInputLevel(_ db: Float?) {
        guard let db else {
            inputLevel = 0
            needsDisplay = true
            return
        }
        inputLevel = max(0, min(1, (CGFloat(db) + 60) / 60))
        needsDisplay = true
    }

    func updateMemoryHigh(_ memoryHigh: Bool) {
        guard self.memoryHigh != memoryHigh else { return }
        self.memoryHigh = memoryHigh
        needsDisplay = true
    }

    func reset() {
        renderState = .empty
        bands = Array(repeating: 0, count: 7)
        inputLevel = 0
        memoryHigh = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        NSColor(calibratedWhite: 0.055, alpha: 0.94).setFill()
        background.fill()
        let borderColor = memoryHigh
            ? NSColor.systemOrange.withAlphaComponent(0.82)
            : NSColor(calibratedRed: 0.55, green: 0.69, blue: 0.42, alpha: 0.58)
        borderColor.setStroke()
        background.lineWidth = memoryHigh ? 1.6 : 1
        background.stroke()

        if renderState.visibleText.isEmpty {
            drawStatus()
            drawWaveform()
        } else {
            drawTranscript()
        }
    }

    private func drawStatus() {
        let rect = NSRect(
            x: Metrics.horizontalInset,
            y: 0,
            width: bounds.width - Metrics.horizontalInset * 2 - Metrics.waveformWidth,
            height: bounds.height
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        (statusText as NSString).draw(
            in: rect.insetBy(dx: 0, dy: 11),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.9),
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func drawWaveform() {
        let rect = NSRect(
            x: bounds.maxX - Metrics.horizontalInset - Metrics.waveformWidth,
            y: 9,
            width: Metrics.waveformWidth,
            height: bounds.height - 18
        )
        let count = 7
        let gap: CGFloat = 5
        let barWidth = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for index in 0..<count {
            let band = bands.isEmpty ? 0 : CGFloat(bands[index % bands.count])
            let level = max(inputLevel, max(0, min(1, band)))
            let height = max(2, rect.height * (0.18 + level * 0.82))
            let bar = NSRect(
                x: rect.minX + CGFloat(index) * (barWidth + gap),
                y: rect.midY - height / 2,
                width: barWidth,
                height: height
            )
            NSColor(calibratedRed: 0.62, green: 0.76, blue: 0.48, alpha: 0.78).setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    private func drawTranscript() {
        let textRect = bounds.insetBy(dx: Metrics.horizontalInset, dy: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.alignment = .left
        let value = NSMutableAttributedString(
            string: renderState.visibleText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.94),
                .paragraphStyle: paragraph,
            ]
        )
        let stableCount = min(renderState.visibleStableCharacterCount, value.length)
        if stableCount < value.length {
            value.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 0.62),
                ],
                range: NSRange(location: stableCount, length: value.length - stableCount)
            )
        }
        value.draw(
            with: textRect.insetBy(dx: 0, dy: 11),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}
