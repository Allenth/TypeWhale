import AppKit
import QuartzCore

final class RecordingCapsuleView: NSView {
    private enum Metrics {
        static let compactSize = NSSize(width: 176, height: 42)
        static let maxPreviewWidth: CGFloat = 300
        static let horizontalPadding: CGFloat = 18
        static let textViewportHeight: CGFloat = 22
        static let textVerticalOffset: CGFloat = -1.5
        static let animatedTailLimit = 8
        static let firstPreviewMinimumCharacters = 3
        static let preExpandLookaheadCharacters = 2
        static let preExpandExtraWidth: CGFloat = 8
    }

    private var state = "录音中"
    private let textBuffer = CapsuleTextBuffer(
        animatedTailLimit: Metrics.animatedTailLimit,
        firstPreviewMinimumCharacters: Metrics.firstPreviewMinimumCharacters
    )
    private var draftTimer: Timer?
    private var fadeTimer: Timer?
    private var fadeStartIndex: Int?
    private var fadeStartedAt: Date?
    private var smoothedBands = Array(repeating: Float(0.08), count: 7)
    private var retainedPreviewWidth = Metrics.compactSize.width
    private let fadeDuration: TimeInterval = 0.25
    private let draftStepInterval: TimeInterval = 0.075

    /// 顶部信息条（App·模式）占用的高度；内容据此整体下移，居中于信息条以下的区域。
    var contextTopInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// 状态边框颜色：录音倒计时临近/内存偏高时高亮整圈边框作为状态提示；nil 为默认白色描边。
    var statusBorderColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    deinit {
        draftTimer?.invalidate()
        fadeTimer?.invalidate()
    }

    var preferredSize: NSSize {
        let height = Metrics.compactSize.height + contextTopInset
        guard !textBuffer.isEmpty else { return NSSize(width: Metrics.compactSize.width, height: height) }
        let width = max(retainedPreviewWidth, measuredPreviewWidth(for: predictedLayoutDraft))
        return NSSize(width: width, height: height)
    }

    private func measuredPreviewWidth(for text: String) -> CGFloat {
        let measured = (text as NSString).size(withAttributes: draftTextAttributes).width
        return min(
            Metrics.maxPreviewWidth,
            max(Metrics.compactSize.width, ceil(measured) + Metrics.horizontalPadding * 2)
        )
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
        let availableCompactWidth = Metrics.compactSize.width - Metrics.horizontalPadding * 2
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
            for index in smoothedBands.indices {
                let target = index < bands.count ? bands[index] : 0.08
                // 起音快、落音也跟得紧，避免说话时线条拖沓不灵敏。
                let smoothing: Float = target > smoothedBands[index] ? 0.6 : 0.3
                smoothedBands[index] += (target - smoothedBands[index]) * smoothing
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let capsuleRect = bounds.insetBy(dx: 1, dy: 1)
        let radius: CGFloat = 20
        let path = NSBezierPath(roundedRect: capsuleRect, xRadius: radius, yRadius: radius)

        let highlight = NSBezierPath(roundedRect: capsuleRect.insetBy(dx: 1.5, dy: 1.5), xRadius: radius - 1.5, yRadius: radius - 1.5)
        NSGradient(colors: [
            NSColor(calibratedWhite: 1, alpha: 0.18),
            NSColor(calibratedWhite: 1, alpha: 0.00),
        ])?.draw(in: highlight, angle: 90)

        if let statusBorderColor {
            // 状态高亮：先用半透明同色描一圈“光晕”，再描实色边框。
            statusBorderColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 4.5
            path.stroke()
            statusBorderColor.setStroke()
            path.lineWidth = 1.8
            path.stroke()
        } else {
            NSColor(calibratedWhite: 1, alpha: 0.48).setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }

        let textColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        guard !textBuffer.isEmpty else {
            drawRecordingStatus(textColor: textColor)
            return
        }

        let draftAttributes = draftTextAttributes
        let contentHeight = bounds.height - contextTopInset
        let draftRect = NSRect(
            x: Metrics.horizontalPadding,
            y: (contentHeight - Metrics.textViewportHeight) / 2 + Metrics.textVerticalOffset,
            width: bounds.width - Metrics.horizontalPadding * 2,
            height: Metrics.textViewportHeight
        )
        let visible = visibleDraft(in: draftRect, attributes: draftAttributes)
        attributedVisibleDraft(
            visible,
            attributes: draftAttributes,
            baseColor: textColor
        ).draw(in: draftRect)
    }

    private var draftTextAttributes: [NSAttributedString.Key: Any] {
        let draftParagraph = NSMutableParagraphStyle()
        draftParagraph.lineBreakMode = .byClipping
        draftParagraph.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
            .paragraphStyle: draftParagraph,
        ]
    }

    private func drawRecordingStatus(textColor: NSColor) {
        let mutedColor = NSColor(calibratedWhite: 1, alpha: 0.78)
        let stateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .bold),
            .foregroundColor: textColor,
        ]
        let headerY = (bounds.height - contextTopInset - 19) / 2
        let groupWidth: CGFloat = 124
        let groupX = (bounds.width - groupWidth) / 2
        let stateRect = NSRect(x: groupX, y: headerY, width: 58, height: 19)
        state.draw(in: stateRect, withAttributes: stateAttributes)

        drawWaveform(
            in: NSRect(x: groupX + 66, y: headerY - 0.5, width: 58, height: 19),
            color: mutedColor
        )
    }

    private func visibleDraft(in rect: NSRect, attributes: [NSAttributedString.Key: Any]) -> String {
        let source = Array(textBuffer.displayedDraft)
        guard !source.isEmpty else { return "" }
        var low = 1
        var high = min(source.count, 80)
        var best = String(source.suffix(1))
        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(source.suffix(mid))
            let measured = (candidate as NSString).size(withAttributes: attributes)
            if ceil(measured.width) <= rect.width {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    private func attributedVisibleDraft(
        _ visible: String,
        attributes: [NSAttributedString.Key: Any],
        baseColor: NSColor
    ) -> NSAttributedString {
        var adjustedFadeStart: Int?
        if let fadeStartIndex, fadeStartedAt != nil, !visible.isEmpty {
            let hiddenCount = max(0, textBuffer.displayedDraft.count - visible.count)
            let visibleFadeStart = max(0, min(visible.count, fadeStartIndex - hiddenCount))
            adjustedFadeStart = visibleFadeStart
        }
        let value = NSMutableAttributedString(string: visible, attributes: attributes)
        guard let fadeStartedAt, let adjustedFadeStart, !visible.isEmpty else { return value }

        let elapsed = Date().timeIntervalSince(fadeStartedAt)
        let alpha = max(0.18, min(1, elapsed / fadeDuration))
        guard alpha < 1 else { return value }

        guard adjustedFadeStart < visible.count else { return value }
        value.addAttribute(
            .foregroundColor,
            value: baseColor.withAlphaComponent(0.94 * alpha),
            range: NSRange(location: adjustedFadeStart, length: visible.count - adjustedFadeStart)
        )
        return value
    }

    private func setDraftTarget(_ draft: String) {
        switch textBuffer.setTarget(draft) {
        case .reset:
            retainedPreviewWidth = Metrics.compactSize.width
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
            if let fadeStartIndex {
                self.fadeStartIndex = fadeStartIndex
                fadeStartedAt = Date()
                startFadeTimer()
            } else {
                self.fadeStartIndex = nil
                self.fadeStartedAt = nil
            }
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
            if let fadeStartIndex {
                self.fadeStartIndex = fadeStartIndex
                fadeStartedAt = Date()
                startFadeTimer()
            }
        }
        needsDisplay = true
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

    private func drawWaveform(in rect: NSRect, color: NSColor) {
        // 一条水平直线，静音时保持平直，有声音时按声纹强度上下波动。
        let midY = rect.midY
        let maxAmplitude = rect.height / 2 - 1
        let count = smoothedBands.count

        var points: [NSPoint] = [NSPoint(x: rect.minX, y: midY)]
        for (index, band) in smoothedBands.enumerated() {
            let centerDistance = abs(CGFloat(index) - CGFloat(count - 1) / 2) / (CGFloat(count - 1) / 2)
            // 各点权重接近一致，让说话时整条线一起波动（多个折痕），而不是只有中间动。
            let centerWeight = 0.86 + (1 - centerDistance) * 0.22
            // 噪声门限：环境噪声落入死区输出 0，安静时是一条平直线；门限略放低让人声一起就有反应。
            let activeBand = max(0, (CGFloat(band) - 0.13) / 0.87)
            // 接近线性的映射：幅度真正随响度起伏，有动态层次而不是一过门限就顶满。
            let emphasized = activeBand <= 0 ? 0 : pow(activeBand, 0.9)
            let direction: CGFloat = index % 2 == 0 ? 1 : -1
            let offset = emphasized * centerWeight * maxAmplitude * direction
            let x = rect.minX + rect.width * (CGFloat(index) + 0.5) / CGFloat(count)
            points.append(NSPoint(x: x, y: midY + offset))
        }
        points.append(NSPoint(x: rect.maxX, y: midY))

        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}
