import AppKit

@main
struct RecordingPanelModeEmphasisCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let panel = RecordingPanel()
        panel.setContext(appIcon: nil, appName: "Codex", modeName: "开发需求", autoTranslateEnabled: false)

        let button = findModeButton(in: panel.contentView)
        precondition(button.attributedTitle.string == "开发需求")
        precondition(!isAutomaticYellow(button), "Manual mode should use the default capsule label color")

        panel.updateModeEmphasis(.automaticResolved)
        precondition(button.attributedTitle.string == "开发需求")
        precondition(isAutomaticYellow(button), "Automatic resolved mode should be highlighted in yellow")

        panel.updateModeName("润色")
        precondition(button.attributedTitle.string == "润色")
        precondition(isAutomaticYellow(button), "Automatic emphasis should persist when the resolved mode changes")

        panel.updateModeEmphasis(.normal)
        precondition(!isAutomaticYellow(button), "Non-automatic mode should return to the default capsule label color")

        print("RecordingPanelModeEmphasisCheck passed")
    }

    private static func findModeButton(in view: NSView?) -> NSButton {
        guard let view else { fatalError("Missing content view") }
        if let button = view as? NSButton, button.toolTip == "点击切换整理模式" {
            return button
        }
        for subview in view.subviews {
            if let found = tryFindModeButton(in: subview) {
                return found
            }
        }
        fatalError("Mode button not found")
    }

    private static func tryFindModeButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.toolTip == "点击切换整理模式" {
            return button
        }
        for subview in view.subviews {
            if let found = tryFindModeButton(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func isAutomaticYellow(_ button: NSButton) -> Bool {
        guard let color = button.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor else {
            return false
        }
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return rgb.redComponent > 0.95
            && rgb.greenComponent > 0.70
            && rgb.blueComponent < 0.45
    }
}
