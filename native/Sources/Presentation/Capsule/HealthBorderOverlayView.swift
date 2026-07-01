import AppKit

/// 覆盖在毛玻璃胶囊「最前面」的健康呼吸边框。
///
/// 之前绿边由 `RecordingCapsuleView` 绘制，位于毛玻璃材质与信息条之下，视觉上被玻璃层压住、
/// 显得像在窗口后面；同时父层 `masksToBounds` 会把向外扩散的光晕整块裁掉。
/// 这里改为一层独立的置顶视图：
/// - 作为 `visualBackground` 的最后一个子视图（最上层），绿边渲染在文字/信息条之前；
/// - 绿环从玻璃边缘略微内缩，使呼吸光晕（向内 + 向外）都落在玻璃圆角范围内、不被裁切；
/// - `hitTest` 返回 nil，鼠标事件透传给下层的模式标签等控件。
final class HealthBorderOverlayView: NSView {
    private enum Metrics {
        static let breathSeconds: TimeInterval = 2.8
        /// 玻璃背景的圆角，与 RecordingPanel 中 visualBackground.cornerRadius 保持一致。
        static let glassCornerRadius: CGFloat = 21
        /// 绿环相对玻璃边缘的内缩量；同时留作向外光晕的余量，保证光晕不越过玻璃边缘被裁掉。
        static let edgeInset: CGFloat = 4
        /// 向胶囊内部渗透的呼吸光晕宽度（像素）。
        static let innerGlowPixels: CGFloat = 9
    }

    private var breathStartedAt = Date()
    private var breathTimer: Timer?

    /// 本地服务健康时为 true：显示呼吸绿环；紧急状态边框由胶囊绘制并优先，届时此层关闭。
    var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            if isActive {
                breathStartedAt = Date()
                startBreathTimerIfNeeded()
            } else {
                breathTimer?.invalidate()
                breathTimer = nil
            }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    /// 仅作装饰，不拦截鼠标：点击透传给下层（模式标签等）。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit { breathTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        guard isActive else { return }

        let elapsed = Date().timeIntervalSince(breathStartedAt)
        let progress = CGFloat((elapsed.truncatingRemainder(dividingBy: Metrics.breathSeconds)) / Metrics.breathSeconds)
        let breath = 0.5 - cos(progress * 2 * .pi) * 0.5
        let intensity = 0.55 + breath * 0.45
        let green = UITheme.healthGreen

        let ringRect = bounds.insetBy(dx: Metrics.edgeInset, dy: Metrics.edgeInset)
        guard ringRect.width > 0, ringRect.height > 0 else { return }
        let radius = max(1, Metrics.glassCornerRadius - Metrics.edgeInset)
        let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: radius, yRadius: radius)

        drawOuterGlow(around: ringRect, radius: radius, color: green, intensity: intensity)
        drawInnerGlow(inside: ringRect, radius: radius, color: green, intensity: intensity)

        // 主描边：亮度与线宽随呼吸起伏，形成清晰的置顶呼吸感。
        green.withAlphaComponent(0.60 + 0.38 * intensity).setStroke()
        ringPath.lineWidth = 1.4 + 0.5 * intensity
        ringPath.stroke()
    }

    /// 向玻璃边缘方向扩散的柔和外光晕；最多扩散 edgeInset 像素，正好抵到玻璃边缘、不被裁切。
    private func drawOuterGlow(around rect: NSRect, radius: CGFloat, color: NSColor, intensity: CGFloat) {
        let steps = Int(Metrics.edgeInset)
        guard steps > 0 else { return }
        for step in 1...steps {
            let offset = CGFloat(step)
            let falloff = 1 - offset / (Metrics.edgeInset + 1)
            let alpha = 0.22 * intensity * falloff * falloff
            let glowRect = rect.insetBy(dx: -offset, dy: -offset)
            let glowPath = NSBezierPath(
                roundedRect: glowRect,
                xRadius: radius + offset,
                yRadius: radius + offset
            )
            color.withAlphaComponent(alpha).setStroke()
            glowPath.lineWidth = 1.6
            glowPath.stroke()
        }
    }

    /// 向胶囊内部渗透的柔和内光晕：边缘处最亮，向内平方衰减淡出。
    private func drawInnerGlow(inside rect: NSRect, radius: CGFloat, color: NSColor, intensity: CGFloat) {
        let steps = Int(Metrics.innerGlowPixels)
        guard steps > 0 else { return }
        for step in 1...steps {
            let offset = CGFloat(step)
            let falloff = 1 - (offset - 1) / Metrics.innerGlowPixels
            let alpha = 0.30 * intensity * falloff * falloff
            let glowRect = rect.insetBy(dx: offset, dy: offset)
            guard glowRect.width > 0, glowRect.height > 0 else { continue }
            let glowPath = NSBezierPath(
                roundedRect: glowRect,
                xRadius: max(1, radius - offset),
                yRadius: max(1, radius - offset)
            )
            color.withAlphaComponent(alpha).setStroke()
            glowPath.lineWidth = 1.6
            glowPath.stroke()
        }
    }

    private func startBreathTimerIfNeeded() {
        guard breathTimer == nil else { return }
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self, self.isActive else {
                timer.invalidate()
                return
            }
            self.needsDisplay = true
        }
        if let breathTimer {
            RunLoop.main.add(breathTimer, forMode: .common)
        }
    }
}
