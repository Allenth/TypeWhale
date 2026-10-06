import AppKit

@main
struct OpenClawReplyLifecycleUICheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        OpenClawReplyPresenter.shared.clearMessages()
        runMainLoop(seconds: 0.05)

        OpenClawReplyPresenter.shared.showReply("生命周期手动收起测试", duration: 3)
        runMainLoop(seconds: 0.06)
        guard let collapseButton = findView(accessibilityIdentifier: "openclaw-reply-collapse-button") as? NSButton else {
            preconditionFailure("OpenClaw reply window should expose a manual collapse button")
        }
        collapseButton.performClick(nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)
        guard let manualOrb = findView(accessibilityIdentifier: "openclaw-reply-orb-button") as? NSButton else {
            preconditionFailure("Manual collapse should show the OpenClaw lobster orb")
        }
        guard let manualCollapsedField = findTextField(stringValue: "生命周期手动收起测试") else {
            preconditionFailure("Manual collapse should preserve messages for later expansion")
        }
        precondition(
            isEffectivelyHidden(manualCollapsedField),
            "Manual collapse should visually hide the message list"
        )
        manualOrb.performClick(nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)
        precondition(
            findTextField(stringValue: "生命周期手动收起测试").map { !isEffectivelyHidden($0) } == true,
            "Manual collapsed messages should expand from the lobster orb"
        )
        OpenClawReplyPresenter.shared.clearMessages()
        runMainLoop(seconds: 0.05)

        OpenClawReplyPresenter.shared.showReply("生命周期短时收起测试", duration: 0.10)
        runMainLoop(seconds: 0.06)
        precondition(
            findTextField(stringValue: "生命周期短时收起测试") != nil,
            "OpenClaw reply should be visible before the idle timeout expires"
        )

        runMainLoop(seconds: 0.22)
        guard let orb = findView(accessibilityIdentifier: "openclaw-reply-orb-button") as? NSButton else {
            preconditionFailure("OpenClaw reply should collapse into the lobster orb after idle timeout")
        }
        guard let collapsedField = findTextField(stringValue: "生命周期短时收起测试") else {
            preconditionFailure("Collapsed OpenClaw messages should preserve hidden messages for later expansion")
        }
        precondition(
            isEffectivelyHidden(collapsedField),
            "Collapsed OpenClaw messages should visually hide the full message list"
        )

        orb.performClick(nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)
        precondition(
            findTextField(stringValue: "生命周期短时收起测试") != nil,
            "Clicking the OpenClaw lobster orb should expand preserved messages"
        )

        OpenClawReplyPresenter.shared.clearMessages()
        print("OpenClawReplyLifecycleUICheck passed")
    }

    @MainActor
    private static func findView(accessibilityIdentifier: String) -> NSView? {
        for window in NSApplication.shared.windows {
            if let found = findView(in: window.contentView, accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }

    private static func findView(in view: NSView?, accessibilityIdentifier: String) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == accessibilityIdentifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func findTextField(stringValue: String) -> NSTextField? {
        for window in NSApplication.shared.windows {
            if let found = findTextField(in: window.contentView, stringValue: stringValue) {
                return found
            }
        }
        return nil
    }

    private static func findTextField(in view: NSView?, stringValue: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.stringValue == stringValue {
            return field
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview, stringValue: stringValue) {
                return found
            }
        }
        return nil
    }

    private static func runMainLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
        }
    }

    private static func isEffectivelyHidden(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden || candidate.alphaValue <= 0.01 {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}
