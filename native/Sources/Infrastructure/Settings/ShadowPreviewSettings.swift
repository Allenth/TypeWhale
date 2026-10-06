import Foundation

struct ShadowPreviewSettings: Equatable, Sendable {
    let isEnabled: Bool

    static let defaultValue = ShadowPreviewSettings(isEnabled: false)
}

struct ShadowPreviewSettingsStore {
    private static let key = "shadowPreviewExperimentEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ShadowPreviewSettings {
        guard defaults.object(forKey: Self.key) != nil else { return .defaultValue }
        return ShadowPreviewSettings(isEnabled: defaults.bool(forKey: Self.key))
    }

    func save(_ settings: ShadowPreviewSettings) {
        defaults.set(settings.isEnabled, forKey: Self.key)
    }
}

extension Notification.Name {
    static let shadowPreviewSettingDidChange = Notification.Name(
        "TypeWhale.shadowPreviewSettingDidChange"
    )
}
