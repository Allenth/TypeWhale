import AppKit
import Foundation

@MainActor
final class AutoSendCountdownPresenter:
    NSObject,
    AutoSendCountdownPresenting
{
    private let panel = AutoSendCountdownPanel(
        contentRect: NSRect(x: 0, y: 0, width: 164, height: 46),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let background = AutoSendCountdownClickView()
    private let countdownLabel = NSTextField(
        labelWithString: "2.0 秒后发送"
    )
    private let capsuleFrame: () -> CGRect?
    private var onCancel: (() -> Void)?

    init(capsuleFrame: @escaping () -> CGRect? = { nil }) {
        self.capsuleFrame = capsuleFrame
        super.init()
        configurePanel()
        configureContent()
    }

    func show(
        snapshot: AutoSendCountdownSnapshot,
        onCancel: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        update(snapshot: snapshot)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func update(snapshot: AutoSendCountdownSnapshot) {
        let value = ceil(snapshot.remainingSeconds * 10) / 10
        countdownLabel.stringValue = String(
            format: "%.1f 秒后发送",
            max(0, value)
        )
    }

    func dismiss() {
        onCancel = nil
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
    }

    private func configureContent() {
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        countdownLabel.textColor = NSColor(
            calibratedWhite: 1,
            alpha: 0.94
        )
        countdownLabel.alignment = .center
        countdownLabel.setAccessibilityLabel("自动发送倒计时")
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        background.onClick = { [weak self] in
            self?.onCancel?()
        }
        background.setAccessibilityElement(true)
        background.setAccessibilityRole(.button)
        background.setAccessibilityLabel("取消自动发送")
        background.setAccessibilityHelp("点击整条倒计时可取消自动发送")

        let content = NSView()
        content.addSubview(background)
        background.addSubview(countdownLabel)
        panel.contentView = content

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(
                equalTo: content.leadingAnchor
            ),
            background.trailingAnchor.constraint(
                equalTo: content.trailingAnchor
            ),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            countdownLabel.centerXAnchor.constraint(
                equalTo: background.centerXAnchor
            ),
            countdownLabel.centerYAnchor.constraint(
                equalTo: background.centerYAnchor
            ),
            countdownLabel.widthAnchor.constraint(equalToConstant: 132),
        ])
    }

    private func positionOnActiveScreen() {
        let currentCapsuleFrame = capsuleFrame()
        let mouseLocation = NSEvent.mouseLocation
        let capsuleCenter = currentCapsuleFrame.map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        let screen = capsuleCenter.flatMap { center in
            NSScreen.screens.first { $0.frame.contains(center) }
        } ?? NSScreen.screens.first {
            $0.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = AutoSendCountdownLayout.origin(
            overlaySize: panel.frame.size,
            capsuleFrame: currentCapsuleFrame,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(origin)
    }

}

private final class AutoSendCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class AutoSendCountdownClickView: NSVisualEffectView {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
