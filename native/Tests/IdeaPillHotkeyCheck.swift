import ApplicationServices
import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
struct IdeaPillHotkeyCheck {
    static func main() {
        let monitor = HotkeyMonitor()
        let ideaPill = HotkeyBinding(
            kind: .combo,
            keyCode: 35,
            modifierKeyCodes: [HotkeyKeyCodes.leftOption]
        )
        monitor.update(
            primary: .defaultBinding,
            secondary: nil,
            screenshot: .screenshotDefaultBinding,
            secondaryScreenshot: nil,
            screenshotTranslation: .screenshotTranslationDefaultBinding,
            autoTranslate: nil,
            mainWindow: nil,
            ideaPill: ideaPill
        )

        var downCount = 0
        var upCount = 0
        var dictationDownCount = 0
        monitor.onDown = { channel, purpose, binding in
            precondition(channel == .chinese)
            precondition(binding == ideaPill)
            if purpose == .ideaPill {
                downCount += 1
            } else {
                dictationDownCount += 1
            }
        }
        monitor.onUp = { channel, purpose, binding in
            precondition(channel == .chinese)
            precondition(binding == ideaPill)
            precondition(purpose == .ideaPill)
            upCount += 1
        }

        _ = monitor.handleKey(
            event: keyEvent(keyCode: 35, isDown: true, flags: [.maskAlternate]),
            isDown: true
        )
        precondition(downCount == 1, "idea pill combo should trigger its own recording purpose")
        precondition(dictationDownCount == 0, "idea pill shortcut must not start normal dictation")

        _ = monitor.handleKey(
            event: keyEvent(keyCode: 35, isDown: false, flags: []),
            isDown: false
        )
        precondition(upCount == 1, "idea pill combo should receive key up")

        print("IdeaPillHotkeyCheck passed")
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
