import Foundation

enum ASRBackend: String {
    case automatic
}

enum SmartTranslationDirection: String {
    case chineseToEnglish
}

struct AudioInputDevice {
    static let systemDefaultUID = ""
    static let selectionStorageKey = "audioInputDeviceUID"
}

@main
struct ScreenshotArchiveModeStoreCheck {
    static func main() {
        ScreenshotArchiveModeStore.reset()
        precondition(ScreenshotArchiveModeStore.load() == .exhaustiveSummary)

        let supported = ScreenshotArchiveModeStore.supportedModes
        precondition(supported.contains(.exhaustiveSummary))
        precondition(supported.contains(.developerRequirement))
        precondition(supported.contains(.polish))
        precondition(supported.contains(.raw))
        precondition(!supported.contains(.automatic))

        ScreenshotArchiveModeStore.save(.developerRequirement)
        precondition(ScreenshotArchiveModeStore.load() == .developerRequirement)

        ScreenshotArchiveModeStore.save(.automatic)
        precondition(ScreenshotArchiveModeStore.load() == .exhaustiveSummary)

        ScreenshotArchiveModeStore.reset()
        precondition(ScreenshotArchiveModeStore.load() == .exhaustiveSummary)
    }
}
