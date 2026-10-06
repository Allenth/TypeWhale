import AppKit

/// 提案 03「玉弧 Jade Arc」：状态不再靠整圈变色，而是沿药丸圆边走一段进度光弧——
/// 倒计时=消退的暖弧、健康=呼吸的绿弧、内存=收缩的红弧，剩余量做成可量的进度。
/// App 与模式脱离本体，变成悬停在上方的浮动小丸；主体只留状态 + 波形，克制如一枚玉。
final class JadeArcCapsuleView: NSView, CapsuleConcept {
    private enum Metrics {
        static let pillHeight: CGFloat = 44
        static let dockHeight: CGFloat = 18
        static let dockGap: CGFloat = 8
        static let compactWidth: CGFloat = 168
        static let maxWidth: CGFloat = 300
        static let radius: CGFloat = 22
        static let hInset: CGFloat = 18
        static let barCount = 7
        static let countdownFullSeconds: CGFloat = 60
    }

    private struct Arc { var fraction: CGFloat; var color: NSColor; var breathing: Bool }

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
        let height = Metrics.pillHeight + Metrics.dockGap + Metrics.dockHeight
        var width = Metrics.compactWidth
        if !draft.isEmpty {
            let textW = (draft.text as NSString).size(withAttributes: [.font: ConceptPalette.font]).width
            width = Metrics.hInset * 2 + ceil(textW)
        }
        return NSSize(width: min(Metrics.maxWidth, max(Metrics.compactWidth, width)), height: height)
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

    /// 光弧由 meta 自动派生：倒计时/内存 > 健康 > 空闲。openClaw 态让位给徽章、不画弧。
    private func currentArc() -> Arc? {
        guard accent != .openClaw else { return nil }
        if let color = meta.urgencyColor {
            let frac = meta.remainingSeconds.map { max(0.05, min(1, CGFloat($0) / Metrics.countdownFullSeconds)) } ?? 0.5
            return Arc(fraction: frac, color: color, breathing: false)
        }
        if meta.ollamaHealthy { return Arc(fraction: 0.62, color: ConceptPalette.green, breathing: true) }
        return Arc(fraction: 0.5, color: ConceptPalette.mist.withAlphaComponent(0.5), breathing: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSRect(x: 1, y: 1, width: bounds.width - 2, height: Metrics.pillHeight - 2)
        let path = NSBezierPath(roundedRect: pill, xRadius: Metrics.radius, yRadius: Metrics.radius)
        ConceptPalette.hudFill.setFill(); path.fill()
        ConceptPalette.hudEdge.setStroke(); path.lineWidth = 1; path.stroke()

        drawArc(on: pill)
        if hasContext { drawDocks(above: pill) }

        if draft.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: ConceptPalette.stateFont, .foregroundColor: ConceptPalette.text]
            let sz = (meta.stateWord as NSString).size(withAttributes: attrs)
            meta.stateWord.draw(at: NSPoint(x: pill.minX + Metrics.hInset, y: pill.midY - sz.height / 2), withAttributes: attrs)
            drawBars(in: NSRect(x: pill.minX + Metrics.hInset + sz.width + 12, y: pill.midY - 8, width: 46, height: 16))
        } else {
            let attr = draft.attributed(font: ConceptPalette.font, color: ConceptPalette.text)
            let rect = NSRect(x: pill.minX + Metrics.hInset, y: pill.midY - 11, width: pill.width - Metrics.hInset * 2, height: 22)
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            let m = NSMutableAttributedString(attributedString: attr)
            m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
            m.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        if accent == .openClaw { drawClawBadge(on: pill) }
    }

    /// 光弧：沿圆角矩形边框画一段。lineDash 让描边只显示 fraction 比例的一段，相位挪到顶部中点附近。
    private func drawArc(on pill: NSRect) {
        guard let arc = currentArc(), arc.fraction > 0.001 else { return }
        let inset = pill.insetBy(dx: -1.2, dy: -1.2)
        let r = Metrics.radius + 1.2
        let path = NSBezierPath(roundedRect: inset, xRadius: r, yRadius: r)
        let perimeter = 2 * (inset.width + inset.height) - 8 * r + 2 * .pi * r
        var frac = arc.fraction
        if arc.breathing {
            frac = arc.fraction * (0.88 + 0.12 * (0.5 + 0.5 * sin(animator.phase * 1.8)))
        }
        let visible = perimeter * min(1, frac)
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.setLineDash([visible, perimeter], count: 2, phase: -perimeter * 0.25)
        arc.color.withAlphaComponent(arc.breathing ? 0.9 : 1).setStroke()
        path.stroke()
    }

    /// 浮动小丸：App 图标 + 名称、模式，悬在主体上方；状态文案（倒计时/内存）也并入。
    private func drawDocks(above pill: NSRect) {
        let y = pill.maxY + Metrics.dockGap
        var chips: [(text: String, color: NSColor, icon: Bool)] = []
        chips.append((meta.appName.isEmpty ? "未知应用" : meta.appName, ConceptPalette.muted, true))
        chips.append((meta.modeName, accent == .openClaw ? ConceptPalette.claw : ConceptPalette.gold, false))
        if meta.autoTranslate { chips.append(("译", ConceptPalette.gold, false)) }
        if let status = meta.statusText { chips.append((status, meta.urgencyColor ?? ConceptPalette.muted, false)) }

        let widths = chips.map { chipWidth(text: $0.text, hasIcon: $0.icon) }
        let total = widths.reduce(0, +) + CGFloat(chips.count - 1) * 6
        var x = bounds.midX - total / 2
        for (i, chip) in chips.enumerated() {
            let w = widths[i]
            let rect = NSRect(x: x, y: y, width: w, height: Metrics.dockHeight)
            let p = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            ConceptPalette.hudFill.setFill(); p.fill()
            ConceptPalette.hudEdge.setStroke(); p.lineWidth = 1; p.stroke()
            var textX = rect.minX + 8
            if chip.icon {
                let icon = NSRect(x: textX, y: rect.midY - 6, width: 12, height: 12)
                ConceptInfoBar.drawAppIcon(meta.appIcon, in: icon)
                textX = icon.maxX + 5
            }
            let str = NSAttributedString(string: chip.text, attributes: [.font: ConceptPalette.chipFont, .foregroundColor: chip.color])
            str.draw(at: NSPoint(x: textX, y: rect.midY - str.size().height / 2))
            x += w + 6
        }
    }

    private func chipWidth(text: String, hasIcon: Bool) -> CGFloat {
        let t = (text as NSString).size(withAttributes: [.font: ConceptPalette.chipFont]).width
        return ceil(t) + (hasIcon ? 12 + 5 : 0) + 16
    }

    private func drawBars(in rect: NSRect) {
        let gap: CGFloat = 3
        let barW: CGFloat = 2.5
        let vals = bands.values
        let n = min(Metrics.barCount, vals.count)
        for i in 0..<n {
            let active = max(0.12, min(1, (CGFloat(vals[i]) - 0.08) / 0.9))
            let h = rect.height * active
            let x = rect.minX + CGFloat(i) * (barW + gap)
            let bar = NSRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
            ConceptPalette.wave.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }

    private func drawClawBadge(on pill: NSRect) {
        let d: CGFloat = 26
        let rect = NSRect(x: pill.maxX - 12, y: pill.maxY - d + 8, width: d, height: d)
        NSColor(calibratedWhite: 0, alpha: 0.4).setFill()
        NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: -1.5)).fill()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.42, green: 0.05, blue: 0.05, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.01, blue: 0.02, alpha: 1),
        ])?.draw(in: NSBezierPath(ovalIn: rect), angle: -45)
        NSColor(calibratedRed: 1, green: 0.31, blue: 0.24, alpha: 0.72).setStroke()
        let ring = NSBezierPath(ovalIn: rect); ring.lineWidth = 1.2; ring.stroke()
        let emoji = NSAttributedString(string: "🦞", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        emoji.draw(at: NSPoint(x: rect.midX - emoji.size().width / 2, y: rect.midY - emoji.size().height / 2))
    }
}
