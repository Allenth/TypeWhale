import Foundation

struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?
    let isSecureTextEntry: Bool
    let developerGlossary: String?
    let recordingSessionId: String?

    init(
        targetAppName: String?,
        targetBundleIdentifier: String?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil,
        recordingSessionId: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
        self.isSecureTextEntry = isSecureTextEntry
        self.developerGlossary = developerGlossary
        self.recordingSessionId = recordingSessionId
    }

    func withDeveloperGlossary(_ glossary: String?) -> SmartInputContext {
        SmartInputContext(
            targetAppName: targetAppName,
            targetBundleIdentifier: targetBundleIdentifier,
            windowTitle: windowTitle,
            isSecureTextEntry: isSecureTextEntry,
            developerGlossary: glossary,
            recordingSessionId: recordingSessionId
        )
    }
}
