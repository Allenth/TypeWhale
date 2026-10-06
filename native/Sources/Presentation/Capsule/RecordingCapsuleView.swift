import AppKit

final class RecordingCapsuleView: NSView {
    enum InnerGlow {
        case none
        case ideaPill
        case openClaw
    }

    private enum Metrics {
        static let textViewportHeight: CGFloat = 22
        static let textVerticalOffset: CGFloat = -1.5
        static let animatedTailLimit = 8
        static let firstPreviewMinimumCharacters = 3
        static let volatileTailAlpha: CGFloat = 0.72
        static let preExpandLookaheadCharacters = 2
        static let preExpandExtraWidth: CGFloat = 8
        static let ideaPillGlowCoverage: CGFloat = 20
        static let openClawBadgeDiameter: CGFloat = 27
        static let openClawBadgeBodyOverlap: CGFloat = 12
        static let openClawBadgeTopLift: CGFloat = 8
    }

    static let ideaPillBorderColor = NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.69, alpha: 0.98)
    static let openClawBorderColor = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.15, alpha: 0.98)
    static let minimumBodyWidth = MainCapsuleShell.compactSize.width

    private var state = "录音中"
    private let shell = MainCapsuleShell()
    private let textBuffer = CapsuleTextBuffer(
        animatedTailLimit: Metrics.animatedTailLimit,
        firstPreviewMinimumCharacters: Metrics.firstPreviewMinimumCharacters
    )
    private var visibleTextCache = CapsuleVisibleTextCache(maxCharacters: 80)
    private var draftTimer: Timer?
    private var fadeTimer: Timer?
    private var fadeStartIndex: Int?
    private var fadeStartedAt: Date?
    private var waveformMotion = MainCapsuleWaveformMotion()
    private var retainedPreviewWidth = MainCapsuleShell.compactSize.width
    private let fadeDuration: TimeInterval = 0.25
    private let draftStepInterval: TimeInterval = 0.05

    /// 顶部信息条（App·模式）占用的高度；内容据此整体下移，居中于信息条以下的区域。
    var contextTopInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// 状态边框颜色：录音倒计时临近/内存偏高时高亮整圈边框作为状态提示；nil 为默认白色描边。
    var statusBorderColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var innerGlow: InnerGlow = .none {
        didSet { needsDisplay = true }
    }

    var openClawConnectionStatus: OpenClawConnectionStatus = .checking {
        didSet { needsDisplay = true }
    }

    /// 健康呼吸绿环激活时置 true：隐藏默认白色描边，让置顶绿环成为唯一边框，避免内外双层边框。
    var defaultBorderHidden = false {
        didSet {
            guard oldValue != defaultBorderHidden else { return }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    deinit {
        draftTimer?.invalidate()
        fadeTimer?.invalidate()
    }

    var preferredSize: NSSize {
        shell.preferredSize(
            hasText: !textBuffer.isEmpty,
            retainedPreviewWidth: retainedPreviewWidth,
            measuredPreviewWidth: measuredPreviewWidth(for: predictedLayoutDraft),
            contextTopInset: contextTopInset,
            accent: shellAccent
        )
    }

    func materialFrame(for size: NSSize) -> NSRect {
        shell.materialFrame(for: size, accent: shellAccent)
    }

    private func measuredPreviewWidth(for text: String) -> CGFloat {
        let measured = (text as NSString).size(withAttributes: draftTextAttributes).width
        return shell.previewWidth(forMeasuredTextWidth: measured)
    }

    private func retainPreviewWidthIfNeeded() {
        guard !textBuffer.isEmpty else { return }
        retainedPreviewWidth = max(retainedPreviewWidth, measuredPreviewWidth(for: predictedLayoutDraft))
    }

    private var predictedLayoutDraft: String {
        let displayed = textBuffer.displayedDraft
        let target = textBuffer.targetDraft
        guard target.count > displayed.count else { return displayed }
        let predictedCount = min(target.count, displayed.count + Metrics.preExpandLookaheadCharacters)
        let predicted = String(target.prefix(predictedCount))
        let displayedWidth = (displayed as NSString).size(withAttributes: draftTextAttributes).width
        let availableCompactWidth = MainCapsuleShell.compactSize.width - MainCapsuleShell.horizontalPadding * 2
        if displayedWidth > availableCompactWidth * 0.72 {
            return predicted + String(repeating: " ", count: Int(Metrics.preExpandExtraWidth / 4))
        }
        return predicted
    }

    func update(state: String? = nil, draft: String? = nil, bands: [Float]? = nil) {
        if let state {
            self.state = state
        }
        if let draft {
            setDraftTarget(draft)
        }
        if let bands {
            waveformMotion.apply(bands)
        }
        needsDisplay = true
    }

    /// 结构化快照入口：稳定前缀只追加、可变尾部原位修订，避免整串猜测式 diff。
    func update(snapshot: PreviewDisplaySnapshot) {
        applyBufferUpdate(textBuffer.setSnapshot(
            stableCharacterCount: snapshot.stableCharacterCount,
            stableWindowText: snapshot.stableWindowText,
            volatileTailText: snapshot.volatileTailText
        ))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let capsuleRect = capsuleBodyRect()
        let radius = shell.cornerRadius
        let path = NSBezierPath(roundedRect: capsuleRect, xRadius: radius, yRadius: radius)

        let highlight = NSBezierPath(roundedRect: capsuleRect.insetBy(dx: 1.5, dy: 1.5), xRadius: radius - 1.5, yRadius: radius - 1.5)
        NSGradient(colors: [
            UITheme.waterInkAccent.withAlphaComponent(0.16),
            UITheme.waterInkAccent.withAlphaComponent(0.00),
        ])?.draw(in: highlight, angle: 90)

        let renderState = currentRenderState()
        drawInnerGlowIfNeeded(in: capsuleRect, radius: radius, renderState: renderState)

        if let statusBorderColor {
            // 状态高亮：先用半透明同色描一圈“光晕”，再描实色边框。
            statusBorderColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 4.5
            path.stroke()
            statusBorderColor.setStroke()
            path.lineWidth = 1.8
            path.stroke()
        } else if !defaultBorderHidden {
            UITheme.capsuleAccent.withAlphaComponent(0.44).setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }

        let textColor = UITheme.capsuleText
        guard !textBuffer.isEmpty else {
            drawRecordingStatus(
                in: capsuleRect,
                textColor: textColor,
                renderState: renderState
            )
            drawOpenClawBadgeIfNeeded(in: capsuleRect, renderState: renderState)
            return
        }

        let draftAttributes = draftTextAttributes
        let contentHeight = capsuleRect.height - contextTopInset
        let draftRect = NSRect(
            x: capsuleRect.minX + MainCapsuleShell.horizontalPadding,
            y: capsuleRect.minY + (contentHeight - Metrics.textViewportHeight) / 2 + Metrics.textVerticalOffset,
            width: capsuleRect.width - MainCapsuleShell.horizontalPadding * 2,
            height: Metrics.textViewportHeight
        )
        let visible = visibleDraft(
            source: renderState.displayedText,
            in: draftRect,
            attributes: draftAttributes
        )
        attributedVisibleDraft(
            visible,
            renderState: renderState,
            attributes: draftAttributes,
            baseColor: textColor
        ).draw(in: draftRect)
        drawOpenClawBadgeIfNeeded(in: capsuleRect, renderState: renderState)
    }

    private func capsuleBodyRect() -> NSRect {
        shell.bodyRect(in: bounds, accent: shellAccent)
    }

    private var shellAccent: MainCapsuleShellAccent {
        switch innerGlow {
        case .none:
            return .normal
        case .ideaPill:
            return .ideaPill
        case .openClaw:
            return .openClaw
        }
    }

    private var legacyPreviewAccent: PreviewAccent {
        switch innerGlow {
        case .none:
            return .normal
        case .ideaPill:
            return .ideaPill
        case .openClaw:
            return .openClaw
        }
    }

    private func drawInnerGlowIfNeeded(
        in capsuleRect: NSRect,
        radius: CGFloat,
        renderState: MainCapsuleRenderState
    ) {
        guard let purposeGlow = renderState.purposeGlow else { return }

        let fillColor: NSColor
        let strokeColor: NSColor
        switch purposeGlow {
        case .ideaPill:
            fillColor = UITheme.capsuleAccent.withAlphaComponent(0.08)
            strokeColor = UITheme.capsuleAccent
        case .openClaw:
            fillColor = NSColor(calibratedRed: 1.0, green: 0.10, blue: 0.08, alpha: 0.10)
            strokeColor = NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.16, alpha: 1)
        }

        let fillPath = NSBezierPath(roundedRect: capsuleRect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        fillPath.fill()

        let steps = Int(Metrics.ideaPillGlowCoverage)
        for step in 0..<steps {
            let offset = CGFloat(step) + 0.5
            let glowRect = capsuleRect.insetBy(dx: offset, dy: offset)
            guard glowRect.width > 0, glowRect.height > 0 else { continue }

            let progress = CGFloat(step) / CGFloat(max(1, steps - 1))
            let alpha = 0.18 * pow(1 - progress, 1.55)
            let path = NSBezierPath(
                roundedRect: glowRect,
                xRadius: max(1, radius - offset),
                yRadius: max(1, radius - offset)
            )
            strokeColor.withAlphaComponent(alpha).setStroke()
            path.lineWidth = 1.8
            path.stroke()
        }
    }

    private func drawOpenClawBadgeIfNeeded(in capsuleRect: NSRect, renderState: MainCapsuleRenderState) {
        guard let connectionStatus = renderState.openClawConnectionStatus else { return }
        let diameter = Metrics.openClawBadgeDiameter
        let rect = NSRect(
            x: capsuleRect.maxX - Metrics.openClawBadgeBodyOverlap,
            y: capsuleRect.maxY - diameter + Metrics.openClawBadgeTopLift,
            width: diameter,
            height: diameter
        )

        NSColor(calibratedWhite: 0, alpha: 0.34).setFill()
        NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: -1.5)).fill()

        let palette = openClawBadgePalette(for: connectionStatus)
        let shell = NSBezierPath(ovalIn: rect)
        NSGradient(colors: [palette.shellTop, palette.shellBottom])?.draw(in: shell, angle: -45)
        palette.shellStroke.setStroke()
        shell.lineWidth = 1.2
        shell.stroke()

        drawLobster(in: rect.insetBy(dx: 3.2, dy: 3.0), palette: palette)
    }

    private func drawLobster(in rect: NSRect, palette: OpenClawBadgePalette) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        let leftClaw = NSBezierPath()
        leftClaw.move(to: point(0.20, 0.55))
        leftClaw.curve(to: point(0.08, 0.34), controlPoint1: point(0.02, 0.56), controlPoint2: point(-0.01, 0.42))
        leftClaw.curve(to: point(0.30, 0.35), controlPoint1: point(0.17, 0.21), controlPoint2: point(0.30, 0.25))
        leftClaw.curve(to: point(0.20, 0.55), controlPoint1: point(0.37, 0.47), controlPoint2: point(0.31, 0.57))

        let rightClaw = NSBezierPath()
        rightClaw.move(to: point(0.80, 0.55))
        rightClaw.curve(to: point(0.92, 0.34), controlPoint1: point(0.98, 0.56), controlPoint2: point(1.01, 0.42))
        rightClaw.curve(to: point(0.70, 0.35), controlPoint1: point(0.83, 0.21), controlPoint2: point(0.70, 0.25))
        rightClaw.curve(to: point(0.80, 0.55), controlPoint1: point(0.63, 0.47), controlPoint2: point(0.69, 0.57))

        let body = NSBezierPath()
        body.move(to: point(0.50, 0.93))
        body.curve(to: point(0.21, 0.48), controlPoint1: point(0.28, 0.92), controlPoint2: point(0.17, 0.73))
        body.curve(to: point(0.41, 0.16), controlPoint1: point(0.24, 0.30), controlPoint2: point(0.33, 0.20))
        body.line(to: point(0.41, 0.02))
        body.line(to: point(0.49, 0.02))
        body.line(to: point(0.50, 0.15))
        body.line(to: point(0.56, 0.02))
        body.line(to: point(0.64, 0.02))
        body.line(to: point(0.61, 0.16))
        body.curve(to: point(0.79, 0.48), controlPoint1: point(0.70, 0.21), controlPoint2: point(0.76, 0.31))
        body.curve(to: point(0.50, 0.93), controlPoint1: point(0.83, 0.73), controlPoint2: point(0.72, 0.92))
        body.close()

        [leftClaw, rightClaw, body].forEach { path in
            NSGradient(colors: [palette.lobsterHighlight, palette.lobsterMain, palette.lobsterShadow])?.draw(in: path, angle: -65)
            NSColor(calibratedRed: 1, green: 0.58, blue: 0.48, alpha: 0.38).setStroke()
            path.lineWidth = 0.6
            path.stroke()
        }

        let antennaLeft = NSBezierPath()
        antennaLeft.move(to: point(0.42, 0.87))
        antennaLeft.curve(to: point(0.18, 0.96), controlPoint1: point(0.35, 1.02), controlPoint2: point(0.27, 1.04))
        let antennaRight = NSBezierPath()
        antennaRight.move(to: point(0.58, 0.87))
        antennaRight.curve(to: point(0.82, 0.96), controlPoint1: point(0.65, 1.02), controlPoint2: point(0.73, 1.04))
        palette.lobsterMain.setStroke()
        [antennaLeft, antennaRight].forEach {
            $0.lineWidth = 1.05
            $0.lineCapStyle = .round
            $0.stroke()
        }

        NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point(0.36, 0.69).x - 1.7, y: point(0.36, 0.69).y - 1.7, width: 3.4, height: 3.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: point(0.64, 0.69).x - 1.7, y: point(0.64, 0.69).y - 1.7, width: 3.4, height: 3.4)).fill()
        NSColor(calibratedRed: 0.0, green: 0.90, blue: 0.80, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point(0.37, 0.70).x - 0.7, y: point(0.37, 0.70).y - 0.7, width: 1.4, height: 1.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: point(0.65, 0.70).x - 0.7, y: point(0.65, 0.70).y - 0.7, width: 1.4, height: 1.4)).fill()
    }

    private struct OpenClawBadgePalette {
        let shellTop: NSColor
        let shellBottom: NSColor
        let shellStroke: NSColor
        let lobsterHighlight: NSColor
        let lobsterMain: NSColor
        let lobsterShadow: NSColor
    }

    private func openClawBadgePalette(for connectionStatus: MainCapsuleOpenClawConnectionStatus) -> OpenClawBadgePalette {
        switch connectionStatus {
        case .connected:
            return OpenClawBadgePalette(
                shellTop: NSColor(calibratedRed: 0.18, green: 0.015, blue: 0.018, alpha: 0.96),
                shellBottom: NSColor(calibratedRed: 0.40, green: 0.02, blue: 0.025, alpha: 0.96),
                shellStroke: NSColor(calibratedRed: 1, green: 0.30, blue: 0.22, alpha: 0.72),
                lobsterHighlight: NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.38, alpha: 0.92),
                lobsterMain: NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.16, alpha: 1),
                lobsterShadow: NSColor(calibratedRed: 0.70, green: 0.045, blue: 0.05, alpha: 1)
            )
        case .checking:
            return OpenClawBadgePalette(
                shellTop: NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.015, alpha: 0.96),
                shellBottom: NSColor(calibratedRed: 0.52, green: 0.34, blue: 0.02, alpha: 0.96),
                shellStroke: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.18, alpha: 0.78),
                lobsterHighlight: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.32, alpha: 0.96),
                lobsterMain: NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.08, alpha: 1),
                lobsterShadow: NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.015, alpha: 1)
            )
        case .unavailable:
            return OpenClawBadgePalette(
                shellTop: NSColor(calibratedWhite: 0.015, alpha: 0.98),
                shellBottom: NSColor(calibratedRed: 0.09, green: 0.012, blue: 0.014, alpha: 0.98),
                shellStroke: NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.07, alpha: 0.86),
                lobsterHighlight: NSColor(calibratedRed: 0.22, green: 0.04, blue: 0.035, alpha: 0.95),
                lobsterMain: NSColor(calibratedRed: 0.13, green: 0.018, blue: 0.018, alpha: 1),
                lobsterShadow: NSColor(calibratedWhite: 0.01, alpha: 1)
            )
        }
    }

    private lazy var draftTextAttributes: [NSAttributedString.Key: Any] = {
        let draftParagraph = NSMutableParagraphStyle()
        draftParagraph.lineBreakMode = .byClipping
        draftParagraph.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
            .foregroundColor: UITheme.capsuleText,
            .paragraphStyle: draftParagraph,
        ]
    }()

    private func drawRecordingStatus(
        in capsuleRect: NSRect,
        textColor: NSColor,
        renderState: MainCapsuleRenderState
    ) {
        let stateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .bold),
            .foregroundColor: textColor,
        ]
        let headerY = capsuleRect.minY + (capsuleRect.height - contextTopInset - 19) / 2
        let groupWidth: CGFloat = 124
        let groupX = capsuleRect.minX + (capsuleRect.width - groupWidth) / 2
        let stateRect = NSRect(x: groupX, y: headerY, width: 58, height: 19)
        renderState.statusText.draw(in: stateRect, withAttributes: stateAttributes)

        drawWaveform(
            in: NSRect(x: groupX + 66, y: headerY - 0.5, width: 58, height: 19),
            bands: renderState.waveformBands
        )
    }

    private func currentRenderState() -> MainCapsuleRenderState {
        let motion = MainCapsuleTextMotion(
            visibleCharacterCount: textBuffer.displayedDraft.count,
            targetCharacterCount: textBuffer.targetDraft.count,
            stableCharacterCount: textBuffer.displayedVolatileStartIndex
        )
        let statusProjection = MainCapsuleLegacyStatusProjection(statusText: state)
        let purposeProjection = MainCapsuleOpenClawProjection(
            accent: legacyPreviewAccent,
            connectionStatus: openClawConnectionStatus
        )
        return MainCapsuleRenderState(
            state: MainCapsuleState(
                phase: statusProjection.phase,
                purpose: purposeProjection.purpose
            ),
            contentText: textBuffer.targetDraft,
            motion: motion,
            waveform: waveformMotion,
            statusTextOverride: statusProjection.statusTextOverride
        )
    }

    private func visibleDraft(
        source: String,
        in rect: NSRect,
        attributes: [NSAttributedString.Key: Any]
    ) -> String {
        visibleTextCache.resolve(source: source, width: Double(rect.width)) { candidate in
            Double(ceil((candidate as NSString).size(withAttributes: attributes).width))
        }
    }

    private func attributedVisibleDraft(
        _ visible: String,
        renderState: MainCapsuleRenderState,
        attributes: [NSAttributedString.Key: Any],
        baseColor: NSColor
    ) -> NSAttributedString {
        let value = NSMutableAttributedString(string: visible, attributes: attributes)
        guard !visible.isEmpty else { return value }

        let hiddenCount = max(0, renderState.displayedText.count - visible.count)
        // 可变尾部（未定稿）用弱化透明度区分，向用户诚实标注"这一段还可能修订"。
        let volatileStart = max(0, min(visible.count, renderState.visibleStableCharacterCount - hiddenCount))
        if volatileStart < visible.count {
            value.addAttribute(
                .foregroundColor,
                value: baseColor.withAlphaComponent(Metrics.volatileTailAlpha),
                range: NSRange(location: volatileStart, length: visible.count - volatileStart)
            )
        }

        guard let fadeStartedAt, let fadeStartIndex else { return value }
        let elapsed = Date().timeIntervalSince(fadeStartedAt)
        let alpha = max(0.18, min(1, elapsed / fadeDuration))
        guard alpha < 1 else { return value }
        let adjustedFadeStart = max(0, min(visible.count, fadeStartIndex - hiddenCount))
        guard adjustedFadeStart < visible.count else { return value }

        // 淡入以所在区域的基础透明度为上限：稳定区 0.94、可变区弱化值。
        let stableFadeEnd = max(adjustedFadeStart, min(volatileStart, visible.count))
        if adjustedFadeStart < stableFadeEnd {
            value.addAttribute(
                .foregroundColor,
                value: baseColor.withAlphaComponent(0.94 * alpha),
                range: NSRange(location: adjustedFadeStart, length: stableFadeEnd - adjustedFadeStart)
            )
        }
        let volatileFadeStart = max(adjustedFadeStart, volatileStart)
        if volatileFadeStart < visible.count {
            value.addAttribute(
                .foregroundColor,
                value: baseColor.withAlphaComponent(Metrics.volatileTailAlpha * alpha),
                range: NSRange(location: volatileFadeStart, length: visible.count - volatileFadeStart)
            )
        }
        return value
    }

    private func setDraftTarget(_ draft: String) {
        applyBufferUpdate(textBuffer.setTarget(draft))
    }

    private func applyBufferUpdate(_ update: CapsuleTextBufferUpdate) {
        switch update {
        case .reset:
            retainedPreviewWidth = MainCapsuleShell.compactSize.width
            draftTimer?.invalidate()
            draftTimer = nil
            fadeTimer?.invalidate()
            fadeTimer = nil
            fadeStartIndex = nil
            fadeStartedAt = nil
            needsDisplay = true
        case .ignored:
            needsDisplay = true
        case .updated(let fadeStartIndex, let needsDraftTimer, let shouldStopDraftTimer):
            retainPreviewWidthIfNeeded()
            if shouldStopDraftTimer {
                draftTimer?.invalidate()
                draftTimer = nil
            }
            updateFade(startingAt: fadeStartIndex)
            if needsDraftTimer {
                startDraftTimerIfNeeded()
            }
            needsDisplay = true
        }
    }

    private func startDraftTimerIfNeeded() {
        guard textBuffer.displayedDraft != textBuffer.targetDraft, draftTimer == nil else { return }
        draftTimer = Timer.scheduledTimer(withTimeInterval: draftStepInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.advanceDisplayedDraft()
        }
        if let draftTimer {
            RunLoop.main.add(draftTimer, forMode: .common)
        }
    }

    private func advanceDisplayedDraft() {
        switch textBuffer.advance() {
        case .finished:
            draftTimer?.invalidate()
            draftTimer = nil
        case .refreshedAndFinished:
            draftTimer?.invalidate()
            draftTimer = nil
        case .advanced(let fadeStartIndex):
            updateFade(startingAt: fadeStartIndex)
        }
        needsDisplay = true
    }

    private func updateFade(startingAt index: Int?) {
        guard let index else {
            fadeStartIndex = nil
            fadeStartedAt = nil
            return
        }
        fadeStartIndex = index
        fadeStartedAt = Date()
        startFadeTimer()
    }

    private func startFadeTimer() {
        if fadeTimer != nil { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if let fadeStartedAt = self.fadeStartedAt,
               Date().timeIntervalSince(fadeStartedAt) >= self.fadeDuration {
                self.fadeStartIndex = nil
                self.fadeStartedAt = nil
                self.fadeTimer = nil
                timer.invalidate()
            }
            self.needsDisplay = true
        }
        if let fadeTimer {
            RunLoop.main.add(fadeTimer, forMode: .common)
        }
    }

    private func drawWaveform(in rect: NSRect, bands: [Float]) {
        // 与主程序统一：静音平直、出声时整条线上下波动（详见 WaveformRenderer，1.4 折线机制）。
        let (line, activity) = WaveformRenderer.makePath(bands: bands, in: rect)
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.lineWidth = UITheme.waveformLiveLineWidth + 2.6
        UITheme.waveformGlowColor(activity: activity).setStroke()
        line.stroke()
        line.lineWidth = UITheme.waveformLiveLineWidth
        UITheme.waveformStrokeColor(activity: activity).setStroke()
        line.stroke()
    }
}
