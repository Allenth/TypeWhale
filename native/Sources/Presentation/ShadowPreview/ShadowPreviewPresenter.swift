import AppKit

extension ShadowPreviewCoordinator {
    convenience init() {
        self.init(presenter: ShadowPreviewPresenter())
    }
}

@MainActor
final class ShadowPreviewPresenter: ShadowPreviewPresenting {
    static let panelSize = NSSize(width: 252, height: 40)
    private let panel: ShadowPreviewPanel
    private let shadowView = ShadowPreviewView()

    init() {
        panel = ShadowPreviewPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = shadowView
    }

    func apply(_ state: PreviewViewState) {
        shadowView.apply(state)
    }

    func show(adjacentTo productionFrame: CGRect) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(productionFrame) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = ShadowPreviewLayout.frame(
            productionFrame: productionFrame,
            shadowSize: Self.panelSize,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hideImmediately() {
        panel.orderOut(nil)
    }
}

private final class ShadowPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
