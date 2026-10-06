import ApplicationServices
import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
struct OpenClawHotkeyCheck {
    static func main() {
        HotkeyBinding.clear(storageKey: HotkeyBinding.openClawStorageKey)
        precondition(HotkeyBinding.loadOpenClaw() == nil, "OpenClaw should not have a default activation key")

        let monitor = HotkeyMonitor()
        let openClaw = HotkeyBinding(kind: .combo, keyCode: HotkeyKeyCodes.f6, modifierKeyCodes: [])
        monitor.update(
            primary: .defaultBinding,
            secondary: nil,
            screenshot: .screenshotDefaultBinding,
            secondaryScreenshot: nil,
            screenshotTranslation: .screenshotTranslationDefaultBinding,
            autoTranslate: nil,
            mainWindow: nil,
            ideaPill: nil,
            openClaw: nil
        )
        var noBindingTriggered = false
        monitor.onDown = { _, purpose, _ in
            if purpose == .openClawChat { noBindingTriggered = true }
        }
        _ = monitor.handleKey(
            event: keyEvent(keyCode: HotkeyKeyCodes.f6, isDown: true, flags: []),
            isDown: true
        )
        precondition(!noBindingTriggered, "OpenClaw should not trigger before the user sets an activation key")

        monitor.update(
            primary: .defaultBinding,
            secondary: nil,
            screenshot: .screenshotDefaultBinding,
            secondaryScreenshot: nil,
            screenshotTranslation: .screenshotTranslationDefaultBinding,
            autoTranslate: nil,
            mainWindow: nil,
            ideaPill: nil,
            openClaw: openClaw
        )

        var openClawDownCount = 0
        var openClawUpCount = 0
        var dictationDownCount = 0
        monitor.onDown = { channel, purpose, binding in
            precondition(channel == .chinese)
            precondition(binding == openClaw)
            if purpose == .openClawChat {
                openClawDownCount += 1
            } else {
                dictationDownCount += 1
            }
        }
        monitor.onUp = { channel, purpose, binding in
            precondition(channel == .chinese)
            precondition(binding == openClaw)
            precondition(purpose == .openClawChat)
            openClawUpCount += 1
        }

        _ = monitor.handleKey(
            event: keyEvent(keyCode: HotkeyKeyCodes.f6, isDown: true, flags: []),
            isDown: true
        )
        precondition(openClawDownCount == 1, "F6 should trigger OpenClaw recording purpose")
        precondition(dictationDownCount == 0, "F6 must not start normal dictation")

        _ = monitor.handleKey(
            event: keyEvent(keyCode: HotkeyKeyCodes.f6, isDown: false, flags: []),
            isDown: false
        )
        precondition(openClawUpCount == 1, "F6 should receive OpenClaw key up")

        let invalidBinding = HotkeyBinding(
            kind: .combo,
            keyCode: 178,
            modifierKeyCodes: [HotkeyKeyCodes.function]
        )
        invalidBinding.save(storageKey: HotkeyBinding.openClawStorageKey)
        let recovered = HotkeyBinding.loadOpenClaw()
        precondition(recovered == nil, "Unknown OpenClaw key codes should recover to an unset activation key")

        print("OpenClawHotkeyCheck passed")
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
