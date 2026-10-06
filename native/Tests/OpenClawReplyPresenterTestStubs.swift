import AppKit

enum ToastStyle {
    case success
    case info
    case warning
    case error
}

@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()
    func show(_ message: String, style: ToastStyle = .success, duration: TimeInterval? = 1.6) {}
}

enum OpenClawVoicePlaybackNotification {
    static let didStartSpeaking = Notification.Name("TypeWhale.Tests.OpenClawVoice.didStartSpeaking")
    static let didStopSpeaking = Notification.Name("TypeWhale.Tests.OpenClawVoice.didStopSpeaking")
}

final class OpenClawVoicePlayer {
    static let shared = OpenClawVoicePlayer()
    func stop() {}
}

struct OpenClawVoiceSettings {
    var enabled: Bool
}

struct OpenClawVoiceSettingsStore {
    static let standard = OpenClawVoiceSettingsStore()
    func load() -> OpenClawVoiceSettings { OpenClawVoiceSettings(enabled: true) }
    func save(_ settings: OpenClawVoiceSettings) {}
}
