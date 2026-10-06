import AppKit

@main
struct MainCapsulePanelShellCheck {
    static func main() {
        keepsInitialWindowSizeStable()
        expandsForTopInfoBarAndClampsToScreen()
        anchorsPanelAtBottomCenter()
        laysOutContentAndMaterialFrames()
        print("MainCapsulePanelShellCheck passed")
    }

    private static func keepsInitialWindowSizeStable() {
        let shell = MainCapsulePanelShell()
        precondition(shell.initialContentSize == NSSize(width: 164, height: 44))
    }

    private static func expandsForTopInfoBarAndClampsToScreen() {
        let shell = MainCapsulePanelShell()
        let visibleFrame = NSRect(x: 0, y: 0, width: 360, height: 800)

        let normal = shell.panelSize(
            bodySize: NSSize(width: 220, height: 64),
            requiredTopInfoBarWidth: nil,
            minimumBodyWidth: 176,
            rightOverhang: 0,
            screenVisibleFrame: visibleFrame
        )
        precondition(normal == NSSize(width: 220, height: 64))

        let expanded = shell.panelSize(
            bodySize: NSSize(width: 220, height: 64),
            requiredTopInfoBarWidth: 260,
            minimumBodyWidth: 176,
            rightOverhang: 0,
            screenVisibleFrame: visibleFrame
        )
        precondition(expanded == NSSize(width: 288, height: 64))

        let expandedWithOpenClawOverhang = shell.panelSize(
            bodySize: NSSize(width: 278, height: 73),
            requiredTopInfoBarWidth: 260,
            minimumBodyWidth: 176,
            rightOverhang: 18,
            screenVisibleFrame: visibleFrame
        )
        precondition(expandedWithOpenClawOverhang == NSSize(width: 306, height: 73))

        let clamped = shell.panelSize(
            bodySize: NSSize(width: 500, height: 64),
            requiredTopInfoBarWidth: 600,
            minimumBodyWidth: 176,
            rightOverhang: 0,
            screenVisibleFrame: visibleFrame
        )
        precondition(clamped == NSSize(width: 312, height: 64))
    }

    private static func anchorsPanelAtBottomCenter() {
        let shell = MainCapsulePanelShell()
        let frame = shell.targetFrame(
            panelSize: NSSize(width: 200, height: 50),
            screenVisibleFrame: NSRect(x: 10, y: 20, width: 500, height: 800)
        )

        precondition(frame == NSRect(x: 160, y: 63, width: 200, height: 50))
    }

    private static func laysOutContentAndMaterialFrames() {
        let shell = MainCapsulePanelShell()
        let frames = shell.layoutFrames(
            panelSize: NSSize(width: 278, height: 73),
            materialFrame: NSRect(x: 0, y: 0, width: 260, height: 64)
        )

        precondition(frames.contentRoot == NSRect(x: 0, y: 0, width: 278, height: 73))
        precondition(frames.capsule == NSRect(x: 0, y: 0, width: 278, height: 73))
        precondition(frames.visualBackground == NSRect(x: 0, y: 0, width: 260, height: 64))
    }
}
