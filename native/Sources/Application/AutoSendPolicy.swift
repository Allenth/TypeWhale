import Foundation

struct AutoSendPolicy {
    func action(
        configuration: AutoSendConfiguration,
        purpose: SpeechInputPurpose,
        text: String,
        targetBundleIdentifier: String?,
        isTranslated: Bool
    ) -> PostPasteAction {
        guard configuration.isEnabled,
              purpose == .dictation,
              !isTranslated,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bundleID = targetBundleIdentifier,
              !bundleID.isEmpty else {
            return .none
        }
        return configuration.actionsByBundleID[bundleID] ?? .none
    }
}
