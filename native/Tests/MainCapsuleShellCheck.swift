import AppKit

@main
struct MainCapsuleShellCheck {
    static func main() {
        keepsNormalBodySizeInsideContentBounds()
        accountsForOpenClawBadgeOverhang()
        exposesStableBodyRectForDrawing()
        print("MainCapsuleShellCheck passed")
    }

    private static func keepsNormalBodySizeInsideContentBounds() {
        let shell = MainCapsuleShell()
        let size = shell.preferredSize(
            hasText: false,
            retainedPreviewWidth: 176,
            measuredPreviewWidth: 176,
            contextTopInset: 22,
            accent: .normal
        )

        precondition(size == NSSize(width: 176, height: 64))
        precondition(shell.materialFrame(for: size, accent: .normal) == NSRect(x: 0, y: 0, width: 176, height: 64))
        precondition(shell.bodyRect(in: NSRect(origin: .zero, size: size), accent: .normal) == NSRect(x: 1, y: 1, width: 174, height: 62))
    }

    private static func accountsForOpenClawBadgeOverhang() {
        let shell = MainCapsuleShell()
        let size = shell.preferredSize(
            hasText: true,
            retainedPreviewWidth: 240,
            measuredPreviewWidth: 260,
            contextTopInset: 22,
            accent: .openClaw
        )

        precondition(size == NSSize(width: 278, height: 73))
        precondition(shell.materialFrame(for: size, accent: .openClaw) == NSRect(x: 0, y: 0, width: 260, height: 64))
    }

    private static func exposesStableBodyRectForDrawing() {
        let shell = MainCapsuleShell()
        let bounds = NSRect(x: 0, y: 0, width: 278, height: 73)
        let body = shell.bodyRect(in: bounds, accent: .openClaw)

        precondition(body == NSRect(x: 1, y: 1, width: 258, height: 62))
        precondition(shell.cornerRadius == 20)
    }
}
