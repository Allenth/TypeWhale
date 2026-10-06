import AppKit

struct MainCapsulePanelFrames: Equatable {
    let contentRoot: NSRect
    let capsule: NSRect
    let visualBackground: NSRect
}

struct MainCapsulePanelShell {
    static let initialContentSize = NSSize(width: 164, height: 44)

    let infoBarHorizontalInset: CGFloat = 14
    let screenHorizontalMargin: CGFloat = 24
    let bottomAnchorOffset: CGFloat = 68

    var initialContentSize: NSSize {
        Self.initialContentSize
    }

    func panelSize(
        bodySize: NSSize,
        requiredTopInfoBarWidth: CGFloat?,
        minimumBodyWidth: CGFloat,
        rightOverhang: CGFloat,
        screenVisibleFrame: NSRect
    ) -> NSSize {
        var width = bodySize.width
        if let requiredTopInfoBarWidth {
            width = max(width, ceil(requiredTopInfoBarWidth) + infoBarHorizontalInset * 2 + max(0, rightOverhang))
        }
        width = min(width, max(minimumBodyWidth, screenVisibleFrame.width - screenHorizontalMargin * 2))
        return NSSize(width: width, height: bodySize.height)
    }

    func targetFrame(
        panelSize: NSSize,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        let anchorCenter = NSPoint(
            x: screenVisibleFrame.midX,
            y: screenVisibleFrame.minY + bottomAnchorOffset
        )
        return NSRect(
            x: anchorCenter.x - panelSize.width / 2,
            y: anchorCenter.y - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    func layoutFrames(
        panelSize: NSSize,
        materialFrame: NSRect
    ) -> MainCapsulePanelFrames {
        let root = NSRect(origin: .zero, size: panelSize)
        return MainCapsulePanelFrames(
            contentRoot: root,
            capsule: root,
            visualBackground: materialFrame
        )
    }
}
