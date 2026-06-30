import ApplicationServices
import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
struct HotkeyModifierConflictCheck {
    static func main() {
        let monitor = HotkeyMonitor()
        let rightOption = HotkeyBinding(
            kind: .modifier,
            keyCode: HotkeyKeyCodes.rightOption,
            modifierKeyCodes: []
        )
        monitor.update(
            primary: rightOption,
            secondary: nil,
            screenshot: .screenshotDefaultBinding,
            secondaryScreenshot: nil,
            screenshotTranslation: .screenshotTranslationDefaultBinding,
            autoTranslate: nil,
            mainWindow: nil
        )

        var speechDownCount = 0
        var speechUpCount = 0
        var screenshotCount = 0
        monitor.onDown = { _, binding in
            precondition(binding == rightOption)
            speechDownCount += 1
        }
        monitor.onUp = { _, binding in
            precondition(binding == rightOption)
            speechUpCount += 1
        }
        monitor.onScreenshot = {
            screenshotCount += 1
        }

        _ = monitor.handleFlagsChanged(event: modifierEvent(keyCode: HotkeyKeyCodes.rightOption, flags: [.maskAlternate]))
        _ = monitor.handleFlagsChanged(event: modifierEvent(keyCode: HotkeyKeyCodes.rightOption, flags: []))

        precondition(speechDownCount == 1, "right Option speech shortcut should receive key down")
        precondition(speechUpCount == 1, "right Option speech shortcut should receive key up")
        precondition(screenshotCount == 0, "conflicting screenshot shortcut must not swallow or fire")

        print("HotkeyModifierConflictCheck passed")
    }

    private static func modifierEvent(keyCode: Int, flags: CGEventFlags) -> CGEvent {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        ) else {
            fatalError("Unable to create CGEvent")
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        return event
    }
}
