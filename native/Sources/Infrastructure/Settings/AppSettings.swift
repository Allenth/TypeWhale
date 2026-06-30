import Foundation

/// 实时预览窗主题：默认胶囊（现状）/ 刘海主题。
enum PreviewTheme: String {
    case classic
    case notch

    static let `default`: PreviewTheme = .classic
}

struct MainViewSettings {
    var realtimePreviewEnabled: Bool
    var autoFinishAfterPauseEnabled: Bool
    var duckSystemAudioWhileRecordingEnabled: Bool
    var micVoiceProcessingEnabled: Bool
    var audioInputDeviceUID: String
    var asrBackend: ASRBackend
    var smartRewritePreference: SmartRewritePreference
    var autoTranslateEnabled: Bool
    var translationDirection: SmartTranslationDirection
    var previewTheme: PreviewTheme
}

enum AppSettingsStore {
    private static let realtimeKey = "realtime"
    private static let autoFinishAfterPauseKey = "autoFinishAfterPause"
    private static let duckSystemAudioWhileRecordingKey = "duckSystemAudioWhileRecording"
    private static let micVoiceProcessingKey = "micVoiceProcessing"
    private static let audioInputDeviceUIDKey = AudioInputDevice.selectionStorageKey
    private static let asrBackendKey = "asrBackend"
    private static let smartRewritePreferenceKey = "smartRewritePreference"
    private static let autoTranslateEnabledKey = "autoTranslateEnabled"
    private static let translationDirectionKey = "translationDirection"
    private static let previewThemeKey = "previewTheme"

    static func loadMainViewSettings() -> MainViewSettings {
        MainViewSettings(
            realtimePreviewEnabled: UserDefaults.standard.object(forKey: realtimeKey) == nil || UserDefaults.standard.bool(forKey: realtimeKey),
            autoFinishAfterPauseEnabled: UserDefaults.standard.bool(forKey: autoFinishAfterPauseKey),
            duckSystemAudioWhileRecordingEnabled: UserDefaults.standard.bool(forKey: duckSystemAudioWhileRecordingKey),
            micVoiceProcessingEnabled: UserDefaults.standard.bool(forKey: micVoiceProcessingKey),
            audioInputDeviceUID: UserDefaults.standard.string(forKey: audioInputDeviceUIDKey) ?? AudioInputDevice.systemDefaultUID,
            asrBackend: ASRBackend(
                rawValue: UserDefaults.standard.string(forKey: asrBackendKey) ?? ""
            ) ?? .automatic,
            smartRewritePreference: SmartRewritePreference(
                rawValue: UserDefaults.standard.string(forKey: smartRewritePreferenceKey) ?? ""
            ) ?? .automatic,
            autoTranslateEnabled: UserDefaults.standard.bool(forKey: autoTranslateEnabledKey),
            translationDirection: SmartTranslationDirection(
                rawValue: UserDefaults.standard.string(forKey: translationDirectionKey) ?? ""
            ) ?? .chineseToEnglish,
            previewTheme: PreviewTheme(
                rawValue: UserDefaults.standard.string(forKey: previewThemeKey) ?? ""
            ) ?? .default
        )
    }

    static func save(_ settings: MainViewSettings) {
        UserDefaults.standard.set(settings.realtimePreviewEnabled, forKey: realtimeKey)
        UserDefaults.standard.set(settings.autoFinishAfterPauseEnabled, forKey: autoFinishAfterPauseKey)
        UserDefaults.standard.set(settings.duckSystemAudioWhileRecordingEnabled, forKey: duckSystemAudioWhileRecordingKey)
        UserDefaults.standard.set(settings.micVoiceProcessingEnabled, forKey: micVoiceProcessingKey)
        if settings.audioInputDeviceUID.isEmpty {
            UserDefaults.standard.removeObject(forKey: audioInputDeviceUIDKey)
        } else {
            UserDefaults.standard.set(settings.audioInputDeviceUID, forKey: audioInputDeviceUIDKey)
        }
        UserDefaults.standard.set(settings.asrBackend.rawValue, forKey: asrBackendKey)
        UserDefaults.standard.set(settings.smartRewritePreference.rawValue, forKey: smartRewritePreferenceKey)
        UserDefaults.standard.set(settings.autoTranslateEnabled, forKey: autoTranslateEnabledKey)
        UserDefaults.standard.set(settings.translationDirection.rawValue, forKey: translationDirectionKey)
        UserDefaults.standard.set(settings.previewTheme.rawValue, forKey: previewThemeKey)
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

enum BacklogDirectoryStore {
    private static let directoryKey = "backlogDirectory"

    static var defaultDirectory: URL {
        URL(fileURLWithPath: "/Users/waykingah/Movies/github/Obsidian/0.1 backlog需求池", isDirectory: true)
    }

    static var directory: URL {
        guard let savedPath = UserDefaults.standard.string(forKey: directoryKey), !savedPath.isEmpty else {
            return ensureDirectory(defaultDirectory)
        }
        return ensureDirectory(URL(fileURLWithPath: savedPath, isDirectory: true))
    }

    static var displayName: String {
        let url = directory
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    static func save(_ url: URL) {
        let directoryURL = ensureDirectory(url.standardizedFileURL)
        UserDefaults.standard.set(directoryURL.path, forKey: directoryKey)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: directoryKey)
        _ = ensureDirectory(defaultDirectory)
    }

    static func ensureDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
