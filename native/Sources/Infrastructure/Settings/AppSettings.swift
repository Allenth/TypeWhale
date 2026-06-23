import Foundation

struct MainViewSettings {
    var realtimePreviewEnabled: Bool
    var autoFinishAfterPauseEnabled: Bool
    var duckSystemAudioWhileRecordingEnabled: Bool
    var smartRewritePreference: SmartRewritePreference
    var autoTranslateEnabled: Bool
    var translationDirection: SmartTranslationDirection
}

enum AppSettingsStore {
    private static let realtimeKey = "realtime"
    private static let autoFinishAfterPauseKey = "autoFinishAfterPause"
    private static let duckSystemAudioWhileRecordingKey = "duckSystemAudioWhileRecording"
    private static let smartRewritePreferenceKey = "smartRewritePreference"
    private static let autoTranslateEnabledKey = "autoTranslateEnabled"
    private static let translationDirectionKey = "translationDirection"

    static func loadMainViewSettings() -> MainViewSettings {
        MainViewSettings(
            realtimePreviewEnabled: UserDefaults.standard.object(forKey: realtimeKey) == nil || UserDefaults.standard.bool(forKey: realtimeKey),
            autoFinishAfterPauseEnabled: UserDefaults.standard.bool(forKey: autoFinishAfterPauseKey),
            duckSystemAudioWhileRecordingEnabled: UserDefaults.standard.bool(forKey: duckSystemAudioWhileRecordingKey),
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
        UserDefaults.standard.set(settings.smartRewritePreference.rawValue, forKey: smartRewritePreferenceKey)
        UserDefaults.standard.set(settings.autoTranslateEnabled, forKey: autoTranslateEnabledKey)
        UserDefaults.standard.set(settings.translationDirection.rawValue, forKey: translationDirectionKey)
    }
}
