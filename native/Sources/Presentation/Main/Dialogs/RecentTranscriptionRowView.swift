import AppKit

final class RecentTranscriptionRowView: NSView {
    private let index: Int
    private let onDoubleClick: (Int) -> Void

    init(index: Int, onDoubleClick: @escaping (Int) -> Void) {
        self.index = index
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit is NSButton || hit.superview is NSButton {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount >= 2 {
            onDoubleClick(index)
            return
        }
        super.mouseDown(with: event)
    }
}

