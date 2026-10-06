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
struct IdeaPillRewriteModeStoreCheck {
    static func main() {
        IdeaPillRewriteModeStore.reset()
        precondition(IdeaPillRewriteModeStore.defaultMode == .instantSummary)
        precondition(IdeaPillRewriteModeStore.load() == .instantSummary)
        precondition(SmartRewritePreference.instantSummary.displayName == "即时归纳")
        precondition(SmartRewritePreference.instantSummary.manualMode == .note)

        let supported = IdeaPillRewriteModeStore.supportedModes
        precondition(supported == [
            .instantSummary,
            .developerRequirement,
            .exhaustiveSummary,
            .polish,
            .raw,
        ])
        precondition(!supported.contains(.automatic))
        precondition(!SmartRewritePreference.allCases.contains(.instantSummary))

        IdeaPillRewriteModeStore.save(.developerRequirement)
        precondition(IdeaPillRewriteModeStore.load() == .developerRequirement)

        IdeaPillRewriteModeStore.save(.automatic)
        precondition(IdeaPillRewriteModeStore.load() == .instantSummary)

        IdeaPillRewriteModeStore.reset()
        precondition(IdeaPillRewriteModeStore.load() == .instantSummary)
    }
}
