import AppKit
import ApplicationServices
import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
struct SyntheticMediaHotkeyIsolationCheck {
    static func main() {
        let monitor = HotkeyMonitor()
        let openClaw = HotkeyBinding.mediaPlayBinding
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
        monitor.onDown = { _, purpose, binding in
            precondition(purpose == .openClawChat)
            precondition(binding == openClaw)
            openClawDownCount += 1
        }

        guard let generatedEvent = SyntheticMediaKeyEvent.makePlayPauseEvents()?.first else {
            preconditionFailure("generated media event must be constructible")
        }
        let generatedHandled = monitor.handleSystemDefined(event: generatedEvent)
        precondition(!generatedHandled, "generated media events must pass through to the system")
        precondition(openClawDownCount == 0, "generated media events must not activate OpenClaw")

        guard let physicalEvent = SyntheticMediaKeyEvent.makePlayPauseEvents(
            markAsTypeWhaleGenerated: false
        )?.first else {
            preconditionFailure("physical-like media event must be constructible")
        }
        let physicalHandled = monitor.handleSystemDefined(event: physicalEvent)
        precondition(physicalHandled, "an unmarked physical media binding must retain existing handling")
        precondition(openClawDownCount == 1, "an unmarked physical media event must activate OpenClaw once")

        print("SyntheticMediaHotkeyIsolationCheck passed")
    }
}
