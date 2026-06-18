import Foundation

struct MainViewSettings {
    var realtimePreviewEnabled: Bool
    var autoFinishAfterPauseEnabled: Bool
    var duckSystemAudioWhileRecordingEnabled: Bool
}

enum AppSettingsStore {
    private static let realtimeKey = "realtime"
    private static let autoFinishAfterPauseKey = "autoFinishAfterPause"
    private static let duckSystemAudioWhileRecordingKey = "duckSystemAudioWhileRecording"

    static func loadMainViewSettings() -> MainViewSettings {
        MainViewSettings(
            realtimePreviewEnabled: UserDefaults.standard.object(forKey: realtimeKey) == nil || UserDefaults.standard.bool(forKey: realtimeKey),
            autoFinishAfterPauseEnabled: UserDefaults.standard.bool(forKey: autoFinishAfterPauseKey),
            duckSystemAudioWhileRecordingEnabled: UserDefaults.standard.bool(forKey: duckSystemAudioWhileRecordingKey)
        )
    }

    static func save(_ settings: MainViewSettings) {
        UserDefaults.standard.set(settings.realtimePreviewEnabled, forKey: realtimeKey)
        UserDefaults.standard.set(settings.autoFinishAfterPauseEnabled, forKey: autoFinishAfterPauseKey)
        UserDefaults.standard.set(settings.duckSystemAudioWhileRecordingEnabled, forKey: duckSystemAudioWhileRecordingKey)
    }
}
