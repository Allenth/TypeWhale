import Foundation

struct MainViewSettings {
    var realtimePreviewEnabled: Bool
    var autoFinishAfterPauseEnabled: Bool
    var duckSystemAudioWhileRecordingEnabled: Bool
    var asrBackend: ASRBackend
    var smartRewritePreference: SmartRewritePreference
    var autoTranslateEnabled: Bool
    var translationDirection: SmartTranslationDirection
}

enum AppSettingsStore {
    private static let realtimeKey = "realtime"
    private static let autoFinishAfterPauseKey = "autoFinishAfterPause"
    private static let duckSystemAudioWhileRecordingKey = "duckSystemAudioWhileRecording"
    private static let asrBackendKey = "asrBackend"
    private static let smartRewritePreferenceKey = "smartRewritePreference"
    private static let autoTranslateEnabledKey = "autoTranslateEnabled"
    private static let translationDirectionKey = "translationDirection"

    static func loadMainViewSettings() -> MainViewSettings {
        MainViewSettings(
            realtimePreviewEnabled: UserDefaults.standard.object(forKey: realtimeKey) == nil || UserDefaults.standard.bool(forKey: realtimeKey),
            autoFinishAfterPauseEnabled: UserDefaults.standard.bool(forKey: autoFinishAfterPauseKey),
            duckSystemAudioWhileRecordingEnabled: UserDefaults.standard.bool(forKey: duckSystemAudioWhileRecordingKey),
            asrBackend: ASRBackend(
                rawValue: UserDefaults.standard.string(forKey: asrBackendKey) ?? ""
            ) ?? .automatic,
            smartRewritePreference: SmartRewritePreference(
                rawValue: UserDefaults.standard.string(forKey: smartRewritePreferenceKey) ?? ""
            ) ?? .automatic,
            autoTranslateEnabled: UserDefaults.standard.bool(forKey: autoTranslateEnabledKey),
            translationDirection: SmartTranslationDirection(
                rawValue: UserDefaults.standard.string(forKey: translationDirectionKey) ?? ""
            ) ?? .chineseToEnglish
        )
    }

    static func save(_ settings: MainViewSettings) {
        UserDefaults.standard.set(settings.realtimePreviewEnabled, forKey: realtimeKey)
        UserDefaults.standard.set(settings.autoFinishAfterPauseEnabled, forKey: autoFinishAfterPauseKey)
        UserDefaults.standard.set(settings.duckSystemAudioWhileRecordingEnabled, forKey: duckSystemAudioWhileRecordingKey)
        UserDefaults.standard.set(settings.asrBackend.rawValue, forKey: asrBackendKey)
        UserDefaults.standard.set(settings.smartRewritePreference.rawValue, forKey: smartRewritePreferenceKey)
        UserDefaults.standard.set(settings.autoTranslateEnabled, forKey: autoTranslateEnabledKey)
        UserDefaults.standard.set(settings.translationDirection.rawValue, forKey: translationDirectionKey)
    }
}

enum ScreenshotSaveLocationStore {
    private static let directoryKey = "screenshotSaveDirectory"

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var directory: URL {
        guard let savedPath = UserDefaults.standard.string(forKey: directoryKey), !savedPath.isEmpty else {
            return defaultDirectory
        }
        let url = URL(fileURLWithPath: savedPath, isDirectory: true)
        guard isUsableDirectory(url) else {
            resetToDefault()
            return defaultDirectory
        }
        return url
    }

    static var displayName: String {
        let url = directory
        if url.standardizedFileURL.path == defaultDirectory.standardizedFileURL.path {
            return "下载"
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    static func save(_ url: URL) {
        let directoryURL = url.standardizedFileURL
        guard isUsableDirectory(directoryURL) else {
            resetToDefault()
            return
        }
        UserDefaults.standard.set(directoryURL.path, forKey: directoryKey)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: directoryKey)
    }

    static func isUsableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: url.path)
    }
}
