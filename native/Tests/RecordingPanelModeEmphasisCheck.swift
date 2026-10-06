import AppKit

@main
struct RecordingPanelModeEmphasisCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let panel = RecordingPanel()
        panel.setContext(appIcon: nil, appName: "Codex", modeName: "开发需求", autoTranslateEnabled: false)

        let button = findModeButton(in: panel.contentView)
        let textFields = collectTextFields(in: panel.contentView)
        precondition(textFields.count >= 6, "Expected capsule info bar labels to be present without the hidden dB readout")
        for field in textFields {
            precondition(field.maximumNumberOfLines == 1, "Capsule top label should be capped to one line: \(field.stringValue)")
            precondition(field.cell?.wraps == false, "Capsule top label should not wrap: \(field.stringValue)")
            precondition(field.cell?.isScrollable == true, "Capsule top label should clip/truncate instead of wrapping: \(field.stringValue)")
        }

        precondition(button.attributedTitle.string == "开发需求")
        precondition(
            button.frame.width >= requiredModeTitleWidth(button),
            "Mode title button should be wide enough to render every character in 开发需求"
        )
        precondition(!isAutomaticWaterInkWarning(button), "Manual mode should use the default capsule label color")

        panel.updateModeEmphasis(.automaticResolved)
        precondition(button.attributedTitle.string == "开发需求")
        precondition(isAutomaticWaterInkWarning(button), "Automatic resolved mode should be highlighted in the water-ink warning color")

        panel.updateModeName("润色")
        precondition(button.attributedTitle.string == "润色")
        precondition(isAutomaticWaterInkWarning(button), "Automatic emphasis should persist when the resolved mode changes")

        panel.updateModeName("OpenClaw")
        precondition(button.attributedTitle.string == "OpenClaw")
        precondition(button.cell?.wraps == false, "Mode title should stay on one line instead of wrapping")
        precondition(button.cell?.isScrollable == true, "Mode title should clip/truncate instead of wrapping")
        precondition(modeTitleFontSize(button) <= 10.1, "OpenClaw title should shrink when the full title does not fit")

        panel.updateModeEmphasis(.normal)
        precondition(!isAutomaticWaterInkWarning(button), "Non-automatic mode should return to the default capsule label color")

        let longContextPanel = RecordingPanel()
        longContextPanel.setContext(
            appIcon: nil,
            appName: "Google Chrome Canary",
            modeName: "OpenClaw",
            autoTranslateEnabled: true
        )
        longContextPanel.updateRecordingStatus(remainingSeconds: 355, memoryHigh: false)
        longContextPanel.updateInputLevel(db: -19)
        let longContextTextFields = collectTextFields(in: longContextPanel.contentView)
        precondition(
            !longContextTextFields.contains { $0.stringValue.contains("dB") },
            "Capsule should keep input level internal and must not show the engineering dB readout"
        )
        precondition(
            longContextTextFields.contains { $0.stringValue == "Google Chrome Canary" },
            "Capsule top app name should keep the full source text instead of truncating at assignment time"
        )
        precondition(
            longContextPanel.frame.width > 320,
            "Capsule should grow wider than the old 320pt cap when top labels need more room"
        )
        precondition(
            longContextPanel.frame.width >= requiredTopInfoWidth(in: longContextPanel),
            "Capsule width should fully cover the top info bar content instead of clipping labels"
        )

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

    private static func collectTextFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        if view is NSButton { return [] }
        var result: [NSTextField] = []
        if let field = view as? NSTextField {
            result.append(field)
        }
        for subview in view.subviews {
            result.append(contentsOf: collectTextFields(in: subview))
        }
        return result
    }

    private static func isAutomaticWaterInkWarning(_ button: NSButton) -> Bool {
        guard let color = button.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor else {
            return false
        }
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return rgb.redComponent > 0.78
            && rgb.greenComponent > 0.64
            && rgb.blueComponent > 0.32
            && rgb.blueComponent < 0.58
    }

    private static func modeTitleFontSize(_ button: NSButton) -> CGFloat {
        guard let font = button.attributedTitle.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? NSFont else {
            return .greatestFiniteMagnitude
        }
        return font.pointSize
    }

    private static func requiredModeTitleWidth(_ button: NSButton) -> CGFloat {
        ceil(button.attributedTitle.size().width) + 8
    }

    private static func requiredTopInfoWidth(in panel: RecordingPanel) -> CGFloat {
        guard let infoBar = findTopInfoBar(in: panel.contentView) else {
            fatalError("Top info bar not found")
        }
        infoBar.layoutSubtreeIfNeeded()
        return ceil(infoBar.fittingSize.width) + 28
    }

    private static func findTopInfoBar(in view: NSView?) -> NSStackView? {
        guard let view else { return nil }
        if let stack = view as? NSStackView,
           stack.orientation == .horizontal,
           containsModeButton(in: stack) {
            return stack
        }
        for subview in view.subviews {
            if let found = findTopInfoBar(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func containsModeButton(in view: NSView) -> Bool {
        if let button = view as? NSButton, button.toolTip == "点击切换整理模式" {
            return true
        }
        return view.subviews.contains { containsModeButton(in: $0) }
    }
}
