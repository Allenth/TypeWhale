import AppKit

/// 刘海右侧脉冲：一个随输入强度「呼吸/脉冲」的圆点 + 光晕。
///
/// - 由 `setLevel(_:)` 喂入 0...1 的实时强度（来自波形频段或电平）。
/// - 自带 30fps 定时器：对强度做平滑 + 衰减，并叠加一个轻微的空闲呼吸，
///   使脉冲在停顿时仍「活着」、说话时明显扩张。定时器仅在可见期间运行。
final class NotchPulseView: NSView {
    private var targetLevel: CGFloat = 0
    private var smoothed: CGFloat = 0
    private var phase: CGFloat = 0
    private var timer: Timer?

    override var isOpaque: Bool { false }

    func setLevel(_ level: CGFloat) {
        targetLevel = max(targetLevel, max(0, min(1, level)))
    }

    func startAnimating() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        targetLevel = 0
        smoothed = 0
        phase = 0
        needsDisplay = true
    }

    private func tick() {
        smoothed += (targetLevel - smoothed) * 0.35
        targetLevel *= 0.86 // 衰减：说话时被 setLevel 顶高，停顿时回落
        phase += 0.12
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.5
        guard radius > 1 else { return }

        // 空闲呼吸 + 声音强度，合成总强度。
        let idle = 0.10 + 0.06 * (sin(phase) * 0.5 + 0.5)
        let intensity = min(1, idle + smoothed)

        // 外圈光晕：随强度扩张、提亮。
        let haloR = radius * (0.55 + 0.45 * intensity)
        let halo = NSBezierPath(ovalIn: NSRect(
            x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2
        ))
        UITheme.brandTeal.withAlphaComponent(0.14 + 0.30 * intensity).setFill()
        halo.fill()

        // 实心核心。
        let coreR = radius * (0.30 + 0.16 * intensity)
        let core = NSBezierPath(ovalIn: NSRect(
            x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2
        ))
        UITheme.brandTeal.withAlphaComponent(0.92).setFill()
        core.fill()
    }
}
