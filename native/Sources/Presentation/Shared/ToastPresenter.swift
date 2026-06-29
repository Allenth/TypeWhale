import AppKit
import QuartzCore

enum ToastStyle {
    case success
    case info
    case warning
    case error

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .success: return UITheme.brandTeal
        case .info: return NSColor(calibratedWhite: 1, alpha: 0.85)
        case .warning: return .systemOrange
        case .error: return .systemRed
        }
    }
}

/// 应用内轻量提示（toast）：不抢焦点、点击穿透、自动淡出，不打断用户当前操作。
/// 复用胶囊那套“无边框非激活浮层”的范式；全局单例，同一时刻只显示一条，新提示刷新内容与计时。
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var dismissWorkItem: DispatchWorkItem?
    private var generation = 0
    private let fadeDuration: TimeInterval = 0.18

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true // 点击穿透，绝不打断交互
        panel.becomesKeyOnlyIfNeeded = true
        panel.alphaValue = 0

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.wantsLayer = true
        background.layer?.cornerRadius = 11
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.95)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        background.addSubview(row)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: background.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -9),
        ])
        panel.contentView = content
    }

    func show(_ message: String, style: ToastStyle = .success, duration: TimeInterval = 1.6) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = style.tint
        label.stringValue = message

        panel.layoutIfNeeded()
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: 200, height: 40)
        let size = NSSize(width: min(420, max(120, fitting.width)), height: max(38, fitting.height))
        positionPanel(size: size)

        generation += 1
        let current = generation
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, current == self.generation else { return }
            self.dismiss(generation: current)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismiss(generation: Int) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, generation == self.generation else { return }
            self.panel.orderOut(nil)
        }
    }

    private func positionPanel(size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            panel.setContentSize(size)
            return
        }
        panel.setContentSize(size)
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}
