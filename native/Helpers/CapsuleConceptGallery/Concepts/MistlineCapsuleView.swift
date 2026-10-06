import AppKit

/// 提案 02「雾线 Mistline」：按字幕轨重排——
/// 顶行是信息条（App·模式·翻译·状态），中行状态点 + 实时文字，文字下方发丝级基线波形。
/// 为「边说边读长句」优化；波形降为陪衬不抢视觉。
final class MistlineCapsuleView: NSView, CapsuleConcept {
    private enum Metrics {
        static let height: CGFloat = 56
        static let minWidth: CGFloat = 250
        static let maxWidth: CGFloat = 360
        static let radius: CGFloat = 15
        static let hInset: CGFloat = 14
        static let orbDiameter: CGFloat = 8
        static let orbGap: CGFloat = 9
        static let waveHeight: CGFloat = 10
    }

    private var meta = ConceptMeta()
    private var hasContext = false
    private var draft = ConceptDraft()
    private var bands = ConceptWaveformBands()
    private var accent: ConceptAccent = .normal
    private var claw: ConceptClawStatus = .checking
    private lazy var animator = ConceptAnimator { [weak self] _ in self?.needsDisplay = true }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animator.start()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var conceptPreferredSize: NSSize {
        let source = draft.isEmpty ? meta.stateWord : draft.text
        let textW = (source as NSString).size(withAttributes: [.font: ConceptPalette.font]).width
        let contentW = Metrics.hInset + Metrics.orbDiameter + Metrics.orbGap + ceil(textW) + Metrics.hInset
        let infoW = hasContext ? ConceptInfoBar.width(meta) + Metrics.hInset * 2 : 0
        return NSSize(width: min(Metrics.maxWidth, max(Metrics.minWidth, max(contentW, infoW))), height: Metrics.height)
    }

    func conceptSetContext(appIcon: NSImage?, appName: String, modeName: String, autoTranslate: Bool) {
        meta.appIcon = appIcon; meta.appName = appName; meta.modeName = modeName; meta.autoTranslate = autoTranslate
        hasContext = true; needsDisplay = true
    }
    func conceptUpdate(modeName: String) { meta.modeName = modeName; needsDisplay = true }
    func conceptUpdate(autoTranslate: Bool) { meta.autoTranslate = autoTranslate; needsDisplay = true }
    func conceptUpdate(remainingSeconds: Int?, memoryHigh: Bool) {
        meta.remainingSeconds = remainingSeconds; meta.memoryHigh = memoryHigh; needsDisplay = true
    }
    func conceptUpdate(ollamaHealthy: Bool) { meta.ollamaHealthy = ollamaHealthy; needsDisplay = true }
    func conceptUpdate(state: String) { meta.stateWord = state; needsDisplay = true }
    func conceptUpdate(draft text: String, stableCount: Int) {
        draft.text = text; draft.stableCount = stableCount; needsDisplay = true
    }
    func conceptUpdate(bands newBands: [Float]) { bands.apply(newBands); needsDisplay = true }
    func conceptUpdate(accent: ConceptAccent, claw: ConceptClawStatus) {
        self.accent = accent; self.claw = claw; needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: body, xRadius: Metrics.radius, yRadius: Metrics.radius)
        ConceptPalette.hudFill.setFill(); path.fill()
        if let urgency = meta.urgencyColor {
            urgency.withAlphaComponent(0.35).setStroke(); path.lineWidth = 4; path.stroke()
            urgency.setStroke(); path.lineWidth = 1.6; path.stroke()
        } else if meta.ollamaHealthy {
            ConceptPalette.green.withAlphaComponent(0.6 + 0.3 * (0.5 + 0.5 * sin(animator.phase * 1.6))).setStroke()
            path.lineWidth = 1.4; path.stroke()
        } else {
            ConceptPalette.hudEdge.setStroke(); path.lineWidth = 1; path.stroke()
        }

        // 顶行信息条。
        if hasContext {
            let barRect = NSRect(x: body.minX + Metrics.hInset, y: body.maxY - 20, width: body.width - Metrics.hInset * 2, height: 16)
            ConceptInfoBar.draw(meta, in: barRect)
        }

        // 状态点。
        let dotColor: NSColor
        switch accent {
        case .normal: dotColor = ConceptPalette.warm
        case .ideaPill: dotColor = ConceptPalette.mist
        case .openClaw: dotColor = ConceptPalette.claw
        }
        let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(animator.phase * 3.2))
        let midRowY = hasContext ? body.minY + 20 : body.midY
        let orbRect = NSRect(x: body.minX + Metrics.hInset, y: midRowY - Metrics.orbDiameter / 2, width: Metrics.orbDiameter, height: Metrics.orbDiameter)
        dotColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: orbRect.insetBy(dx: -3, dy: -3)).fill()
        dotColor.withAlphaComponent(pulse).setFill()
        NSBezierPath(ovalIn: orbRect).fill()

        // 中行文字。
        let textX = orbRect.maxX + Metrics.orbGap
        let textRect = NSRect(x: textX, y: midRowY - 10, width: body.maxX - Metrics.hInset - textX, height: 20)
        let source: NSAttributedString = draft.isEmpty
            ? NSAttributedString(string: meta.stateWord, attributes: [.font: ConceptPalette.font, .foregroundColor: ConceptPalette.muted])
            : draft.attributed(font: ConceptPalette.font, color: ConceptPalette.text)
        drawTruncated(source, in: textRect)

        // 下行基线波形。
        let waveRect = NSRect(x: textX, y: body.minY + 6, width: min(120, textRect.width), height: Metrics.waveHeight)
        let (line, activity) = ConceptWaveformRenderer.makePath(bands: bands.values, in: waveRect)
        line.lineCapStyle = .round; line.lineJoinStyle = .round
        line.lineWidth = 1.6
        ConceptPalette.wave.withAlphaComponent(0.5 + 0.4 * activity).setStroke()
        line.stroke()
    }

    private func drawTruncated(_ attr: NSAttributedString, in rect: NSRect) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let m = NSMutableAttributedString(attributedString: attr)
        m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
        m.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
