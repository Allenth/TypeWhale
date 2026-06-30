import ApplicationServices
import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
struct HotkeyComboReleaseCheck {
    static func main() {
        let monitor = HotkeyMonitor()
        let secondaryScreenshot = HotkeyBinding(
            kind: .combo,
            keyCode: 6,
            modifierKeyCodes: [HotkeyKeyCodes.leftCommand, HotkeyKeyCodes.leftControl]
        )
        monitor.update(
            primary: .defaultBinding,
            secondary: nil,
            screenshot: .screenshotDefaultBinding,
            secondaryScreenshot: secondaryScreenshot,
            screenshotTranslation: .screenshotTranslationDefaultBinding,
            autoTranslate: nil,
            mainWindow: nil
        )
        var screenshotCount = 0
        monitor.onScreenshot = {
            screenshotCount += 1
        }

        _ = monitor.handleKey(
            event: keyEvent(keyCode: 6, isDown: true, flags: [.maskCommand, .maskControl]),
            isDown: true
        )
        precondition(screenshotCount == 1, "combo screenshot should trigger on first keyDown")

        _ = monitor.handleKey(
            event: keyEvent(keyCode: 6, isDown: false, flags: []),
            isDown: false
        )

        _ = monitor.handleKey(
            event: keyEvent(keyCode: 6, isDown: true, flags: [.maskCommand, .maskControl]),
            isDown: true
        )
        precondition(screenshotCount == 2, "combo screenshot should reset on keyUp even if modifiers were released first")

        print("HotkeyComboReleaseCheck passed")
    }

    private static func keyEvent(keyCode: Int, isDown: Bool, flags: CGEventFlags) -> CGEvent {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: isDown
        ) else {
            fatalError("Unable to create CGEvent")
        }
        event.flags = flags
        return event
    }
}
