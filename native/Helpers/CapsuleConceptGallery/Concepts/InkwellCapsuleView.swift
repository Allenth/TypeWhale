import AppKit

/// 提案 01「墨滴 Inkwell」：折线波形换成一颗会呼吸、涟漪的墨珠，
/// 转写文字像墨在宣纸上洇开——前缘用真实 alpha 渐隐取代硬裁。
/// ideaPill / openClaw 不另画边框，直接改墨珠的色与光，三态共用一个元素。
final class InkwellCapsuleView: NSView, CapsuleConcept {
    private enum Metrics {
        static let bodyHeight: CGFloat = 42
        static let compactWidth: CGFloat = 176
        static let maxWidth: CGFloat = 300
        static let radius: CGFloat = 21
        static let orbDiameter: CGFloat = 26
        static let leftInset: CGFloat = 9
        static let gap: CGFloat = 11
        static let rightPad: CGFloat = 16
        static let fadeZone: CGFloat = 26
        static let infoInset: CGFloat = 20
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

    private var contextInset: CGFloat { hasContext ? Metrics.infoInset : 0 }

    // MARK: CapsuleConcept

    var conceptPreferredSize: NSSize {
        let height = Metrics.bodyHeight + contextInset
        var width = Metrics.compactWidth
        if !draft.isEmpty {
            let textW = (draft.text as NSString).size(withAttributes: [.font: ConceptPalette.font]).width
            width = Metrics.leftInset + Metrics.orbDiameter + Metrics.gap + ceil(textW) + Metrics.rightPad
        }
        if hasContext { width = max(width, ConceptInfoBar.width(meta) + 28) }
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

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 1, dy: 1)
        let body = NSRect(x: outer.minX, y: outer.minY, width: outer.width, height: outer.height - contextInset)
        drawHUD(in: body)

        if hasContext {
            let barRect = NSRect(x: outer.minX + 12, y: body.maxY, width: outer.width - 24, height: contextInset)
            ConceptInfoBar.draw(meta, in: barRect)
        }

        let orbRect = NSRect(
            x: body.minX + Metrics.leftInset,
            y: body.midY - Metrics.orbDiameter / 2,
            width: Metrics.orbDiameter,
            height: Metrics.orbDiameter
        )
        drawOrb(in: orbRect)

        let textX = orbRect.maxX + Metrics.gap
        if draft.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: ConceptPalette.stateFont, .foregroundColor: ConceptPalette.text]
            let size = (meta.stateWord as NSString).size(withAttributes: attrs)
            meta.stateWord.draw(at: NSPoint(x: textX, y: body.midY - size.height / 2), withAttributes: attrs)
        } else {
            drawFadedDraft(in: NSRect(x: textX, y: body.midY - 11, width: body.maxX - textX - 8, height: 22))
        }
    }

    private func drawHUD(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: Metrics.radius, yRadius: Metrics.radius)
        ConceptPalette.hudFill.setFill()
        path.fill()
        // 紧急状态：整圈高亮描边（光晕 + 实线）。
        if let urgency = meta.urgencyColor {
            urgency.withAlphaComponent(0.35).setStroke(); path.lineWidth = 4.5; path.stroke()
            urgency.setStroke(); path.lineWidth = 1.8; path.stroke()
        } else if meta.ollamaHealthy {
            ConceptPalette.green.withAlphaComponent(0.6 + 0.3 * (0.5 + 0.5 * sin(animator.phase * 1.6))).setStroke()
            path.lineWidth = 1.6; path.stroke()
        } else {
            ConceptPalette.hudEdge.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    /// 墨珠：底色随强调态变化；缩放 = 呼吸相位 × 音量活跃度；外圈涟漪按相位向外扩散淡出。
    private func drawOrb(in rect: NSRect) {
        let phase = animator.phase
        let activity = bands.activity
        let breathe = 0.96 + 0.10 * sin(phase * 2.4) + 0.16 * activity
        let d = rect.width * breathe
        let orbRect = NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)

        let core: NSColor
        let halo: NSColor
        switch accent {
        case .normal: core = ConceptPalette.wave; halo = ConceptPalette.mist
        case .ideaPill: core = ConceptPalette.mist; halo = ConceptPalette.mist
        case .openClaw: core = ConceptPalette.claw; halo = ConceptPalette.claw
        }

        let rippleProgress = (phase.truncatingRemainder(dividingBy: 2.6)) / 2.6
        let rippleD = rect.width * (0.9 + rippleProgress * 0.9)
        let rippleRect = NSRect(x: rect.midX - rippleD / 2, y: rect.midY - rippleD / 2, width: rippleD, height: rippleD)
        halo.withAlphaComponent(0.4 * (1 - rippleProgress)).setStroke()
        let ripple = NSBezierPath(ovalIn: rippleRect)
        ripple.lineWidth = 1.4
        ripple.stroke()

        halo.withAlphaComponent(0.28 + 0.22 * activity).setFill()
        NSBezierPath(ovalIn: orbRect.insetBy(dx: -3, dy: -3)).fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.82, green: 0.94, blue: 0.98, alpha: 1),
            core,
            halo.blended(withFraction: 0.5, of: .black) ?? halo,
        ])?.draw(in: NSBezierPath(ovalIn: orbRect), relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
    }

    /// 转写文字：可变尾部已弱化；溢出时对左缘做真实 alpha 渐隐（墨洇入纸的感觉），最新字保持在右侧清晰。
    private func drawFadedDraft(in rect: NSRect) {
        let attr = draft.attributed(font: ConceptPalette.font, color: ConceptPalette.text)
        let fullW = attr.size().width
        let overflow = fullW > rect.width
        let drawRect: NSRect = overflow
            ? NSRect(x: rect.maxX - fullW, y: rect.minY, width: fullW, height: rect.height)
            : rect

        guard let ctx = NSGraphicsContext.current?.cgContext else { attr.draw(in: rect); return }
        ctx.saveGState()
        NSBezierPath(rect: rect).addClip()
        if overflow {
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            attr.draw(with: drawRect, options: [.usesLineFragmentOrigin])
            ctx.setBlendMode(.destinationIn)
            let cs = CGColorSpaceCreateDeviceGray()
            let cg = CGGradient(colorsSpace: cs, colors: [
                NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(cg,
                                   start: CGPoint(x: rect.minX, y: rect.midY),
                                   end: CGPoint(x: rect.minX + Metrics.fadeZone, y: rect.midY),
                                   options: [.drawsAfterEndLocation])
            ctx.endTransparencyLayer()
        } else {
            attr.draw(with: drawRect, options: [.usesLineFragmentOrigin])
        }
        ctx.restoreGState()
    }
}
