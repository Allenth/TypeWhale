import AppKit

// MARK: - 概念胶囊共享工具
//
// 三套「新胶囊」提案（墨滴 / 雾线 / 玉弧）的公共底座。刻意**完全自包含**：
// 只依赖 AppKit，不引用生产的 UITheme / WaveformRenderer / OpenClawConnectionStatus，
// 因此既能作为死代码安全编入主程序（无人引用 = 运行时零影响），
// 也能被独立的预览 gallery 用 swiftc 单独编译。
//
// 色值直接抄自水墨深色主题（native/Sources/Presentation/Shared/UIComponents.swift 深色分支），
// 每个都标注来源，保证与生产胶囊像素级同源；若日后主题调色，同步更新此处即可。

/// 概念胶囊的强调态，镜像生产的 PreviewAccent（此处自定义以保持自包含）。
enum ConceptAccent {
    case normal
    case ideaPill
    case openClaw
}

/// OpenClaw 连接态，镜像生产的 OpenClawConnectionStatus。
enum ConceptClawStatus {
    case checking
    case connected
    case unavailable
}

/// 顶部上下文（App·模式·翻译）与录音/健康状态的集合，三套视图共用一份。
struct ConceptMeta {
    var appIcon: NSImage?
    var appName = ""
    var modeName = "自动"
    var autoTranslate = false
    var remainingSeconds: Int?
    var memoryHigh = false
    var ollamaHealthy = false
    var stateWord = "录音中"

    /// 倒计时/内存的状态文案（无则 nil）。
    var statusText: String? {
        var parts: [String] = []
        if let s = remainingSeconds { parts.append(String(format: "剩 %d:%02d", s / 60, s % 60)) }
        if memoryHigh { parts.append("内存偏高") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 紧急状态色：内存或 <=10s 红、<=30s 橙，否则 nil。
    var urgencyColor: NSColor? {
        if memoryHigh { return .systemRed }
        guard let s = remainingSeconds else { return nil }
        if s <= 10 { return .systemRed }
        if s <= 30 { return .systemOrange }
        return nil
    }
}

/// 概念胶囊统一对外接口，供面板/gallery 用同一套调用驱动三种视图，语义对齐 PreviewPresenting。
protocol CapsuleConcept: NSView {
    /// 当前偏好尺寸（随文字与信息条自适应）。
    var conceptPreferredSize: NSSize { get }
    /// 顶部上下文：App 图标·名称·模式·翻译。
    func conceptSetContext(appIcon: NSImage?, appName: String, modeName: String, autoTranslate: Bool)
    /// 仅更新模式名。
    func conceptUpdate(modeName: String)
    /// 更新自动翻译开关。
    func conceptUpdate(autoTranslate: Bool)
    /// 更新录音倒计时与内存高压。
    func conceptUpdate(remainingSeconds: Int?, memoryHigh: Bool)
    /// 更新本地 Ollama 健康态（驱动健康提示）。
    func conceptUpdate(ollamaHealthy: Bool)
    /// 状态词，如「录音中」。
    func conceptUpdate(state: String)
    /// 实时转写草稿；stableCount 之后的字符视为可变尾部（降透明度）。
    func conceptUpdate(draft: String, stableCount: Int)
    /// 结构化展示快照：稳定前缀只追加 + 可变尾部原位修订。
    func conceptUpdate(snapshot: PreviewDisplaySnapshot)
    /// 归一化后的频段（0...1），驱动波形/墨珠。
    func conceptUpdate(bands: [Float])
    /// 强调态与 OpenClaw 连接态。
    func conceptUpdate(accent: ConceptAccent, claw: ConceptClawStatus)
}

extension CapsuleConcept {
    /// 默认快照消费：拆成稳定窗口 + 可变尾部喂给草稿。
    func conceptUpdate(snapshot: PreviewDisplaySnapshot) {
        let stable = snapshot.stableWindowText
        conceptUpdate(draft: stable + snapshot.volatileTailText, stableCount: stable.count)
    }
}

/// 水墨深色调色板（抄自 UITheme 深色分支）。
enum ConceptPalette {
    /// vibrantDark HUD 材质近似底色：waterInkSurface 深色 rgb(0.075,0.128,0.184)。
    static let hudFill = NSColor(calibratedRed: 0.075, green: 0.128, blue: 0.184, alpha: 0.82)
    static let hudEdge = NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.90, alpha: 0.10)
    /// waterInkText 深色。
    static let text = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 0.96)
    /// waterInkMuted / waterInkFaint 深色。
    static let muted = NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.90, alpha: 0.58)
    static let faint = NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.90, alpha: 0.34)
    /// waterInkMistBlue 深色。
    static let mist = NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.69, alpha: 1)
    /// waveformStroke / waveformGlow 深色。
    static let wave = NSColor(calibratedRed: 0.72, green: 0.90, blue: 0.94, alpha: 1)
    static let waveGlow = NSColor(calibratedRed: 0.42, green: 0.70, blue: 0.80, alpha: 1)
    /// waterInkSuccess / waterInkWarning / waterInkRecording 深色。
    static let green = NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.69, alpha: 1)
    static let gold = NSColor(calibratedRed: 0.90, green: 0.78, blue: 0.46, alpha: 1)
    static let warm = NSColor(calibratedRed: 0.88, green: 0.55, blue: 0.45, alpha: 1)
    /// openClaw 强调红。
    static let claw = NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.16, alpha: 1)

    static let font = NSFont.systemFont(ofSize: 14.5, weight: .semibold)
    static let stateFont = NSFont.systemFont(ofSize: 14.5, weight: .bold)
    static let chipFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let infoFont = NSFont.systemFont(ofSize: 11, weight: .medium)
}

/// 顶部信息条绘制器（App 图标·名称·模式·自动翻译·状态），三套共用同一视觉词汇。
enum ConceptInfoBar {
    static let height: CGFloat = 16
    private static let iconSize: CGFloat = 13
    private static let gap: CGFloat = 5

    private struct Segment { let text: String; let color: NSColor; let bold: Bool }

    private static func segments(_ meta: ConceptMeta) -> [Segment] {
        var segs: [Segment] = []
        if !meta.appName.isEmpty { segs.append(Segment(text: meta.appName, color: ConceptPalette.muted, bold: false)) }
        segs.append(Segment(text: meta.modeName, color: ConceptPalette.gold, bold: true))
        if meta.autoTranslate { segs.append(Segment(text: "自动翻译", color: ConceptPalette.gold, bold: true)) }
        if let status = meta.statusText { segs.append(Segment(text: status, color: meta.urgencyColor ?? ConceptPalette.muted, bold: false)) }
        return segs
    }

    private static func attributed(_ seg: Segment) -> NSAttributedString {
        NSAttributedString(string: seg.text, attributes: [
            .font: seg.bold ? NSFont.systemFont(ofSize: 11, weight: .semibold) : ConceptPalette.infoFont,
            .foregroundColor: seg.color,
        ])
    }

    /// 信息条总宽（含图标与分隔点）。
    static func width(_ meta: ConceptMeta) -> CGFloat {
        let segs = segments(meta)
        guard !segs.isEmpty else { return 0 }
        var w: CGFloat = (meta.appName.isEmpty ? 0 : iconSize + gap)
        let dot = (" · " as NSString).size(withAttributes: [.font: ConceptPalette.infoFont]).width
        for (i, s) in segs.enumerated() {
            w += ceil(attributed(s).size().width)
            if i < segs.count - 1 { w += dot }
        }
        return w
    }

    /// 在 rect 内水平居中绘制信息条。
    static func draw(_ meta: ConceptMeta, in rect: NSRect) {
        let segs = segments(meta)
        guard !segs.isEmpty else { return }
        let total = width(meta)
        var x = rect.midX - total / 2
        let midY = rect.midY
        if !meta.appName.isEmpty {
            let iconRect = NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            drawAppIcon(meta.appIcon, in: iconRect)
            x += iconSize + gap
        }
        let dotAttr = NSAttributedString(string: " · ", attributes: [.font: ConceptPalette.infoFont, .foregroundColor: ConceptPalette.faint])
        for (i, s) in segs.enumerated() {
            let a = attributed(s)
            let sz = a.size()
            a.draw(at: NSPoint(x: x, y: midY - sz.height / 2))
            x += ceil(sz.width)
            if i < segs.count - 1 {
                let dsz = dotAttr.size()
                dotAttr.draw(at: NSPoint(x: x, y: midY - dsz.height / 2))
                x += dsz.width
            }
        }
    }

    /// 画 App 图标；无真实图标时退化为水墨色圆角占位块。
    static func drawAppIcon(_ image: NSImage?, in rect: NSRect) {
        let clip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        if let image {
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGradient(colors: [
                NSColor(calibratedRed: 0.42, green: 0.66, blue: 0.76, alpha: 1),
                ConceptPalette.mist.blended(withFraction: 0.45, of: .black) ?? ConceptPalette.mist,
            ])?.draw(in: clip, angle: -45)
        }
    }
}

/// 频段平滑器（抄自生产 WaveformBands：attack 快、release 慢，静音回到 baseline）。
struct ConceptWaveformBands {
    private(set) var values: [Float]
    private let baseline: Float
    private let attack: Float
    private let release: Float

    init(count: Int = 7, baseline: Float = 0.08, attack: Float = 0.52, release: Float = 0.16) {
        self.values = Array(repeating: baseline, count: count)
        self.baseline = baseline
        self.attack = attack
        self.release = release
    }

    mutating func apply(_ newBands: [Float]) {
        for index in values.indices {
            let target = index < newBands.count ? newBands[index] : baseline
            let smoothing = target > values[index] ? attack : release
            values[index] += (target - values[index]) * smoothing
        }
    }

    /// 峰值活跃度（0...1），供墨珠缩放/波形调色。
    var activity: CGFloat {
        let peak = values.map { max(0, (CGFloat($0) - 0.16) / 0.84) }.max() ?? 0
        return min(1, peak)
    }
}

/// 折线波形（抄自生产 WaveformRenderer 的 1.4 折线机制）：静音平直、出声整条上下波动。
enum ConceptWaveformRenderer {
    static func makePath(bands: [Float], in rect: NSRect) -> (path: NSBezierPath, activity: CGFloat) {
        let count = bands.count
        guard count > 1 else { return (NSBezierPath(), 0) }
        let midY = rect.midY
        let maxAmplitude = rect.height / 2 - 1
        let half = CGFloat(count - 1) / 2
        var peakActivity: CGFloat = 0

        var points: [NSPoint] = [NSPoint(x: rect.minX, y: midY)]
        for (index, band) in bands.enumerated() {
            let centerDistance = abs(CGFloat(index) - half) / half
            let centerWeight = 0.86 + (1 - centerDistance) * 0.22
            let activeBand = max(0, (CGFloat(band) - 0.16) / 0.84)
            peakActivity = max(peakActivity, activeBand)
            let emphasized = activeBand <= 0 ? 0 : pow(activeBand, 0.62)
            let direction: CGFloat = index % 2 == 0 ? 1 : -1
            let offset = emphasized * centerWeight * maxAmplitude * direction
            let x = rect.minX + rect.width * (CGFloat(index) + 0.5) / CGFloat(count)
            points.append(NSPoint(x: x, y: midY + offset))
        }
        points.append(NSPoint(x: rect.maxX, y: midY))

        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        return (path, min(1, peakActivity))
    }
}

/// 概念视图共用的动画节拍：60fps 驱动一个单调递增的相位，供呼吸/涟漪/均衡条使用。
final class ConceptAnimator {
    private(set) var phase: CGFloat = 0
    private var timer: Timer?
    private let onTick: (CGFloat) -> Void

    init(onTick: @escaping (CGFloat) -> Void) {
        self.onTick = onTick
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 1.0 / 60.0
            self.onTick(self.phase)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}

/// 概念胶囊共享的草稿模型：稳定前缀 + 可变尾部（尾部降透明度，向用户诚实标注"还可能改"）。
struct ConceptDraft {
    var text: String = ""
    var stableCount: Int = 0

    var isEmpty: Bool { text.isEmpty }

    /// 构造带可变尾部弱化的富文本。
    func attributed(font: NSFont, color: NSColor, volatileAlpha: CGFloat = 0.5) -> NSAttributedString {
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let chars = Array(text)
        let stable = max(0, min(stableCount, chars.count))
        if stable < chars.count {
            // 定位可变尾部在 UTF-16 中的范围。
            let prefix = String(chars[0..<stable])
            let loc = (prefix as NSString).length
            let len = (text as NSString).length - loc
            if len > 0 {
                value.addAttribute(.foregroundColor,
                                   value: color.withAlphaComponent(volatileAlpha),
                                   range: NSRange(location: loc, length: len))
            }
        }
        return value
    }
}
