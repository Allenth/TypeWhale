import Foundation

struct OnlineASRSettings: Equatable, Sendable {
    let selection: OnlineASRProviderSelection

    static let defaultValue = OnlineASRSettings(selection: .off)
}

struct OnlineASRSettingsStore {
    private static let key = "onlineASRProviderSelection"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> OnlineASRSettings {
        guard let rawValue = defaults.string(forKey: Self.key),
              let selection = OnlineASRProviderSelection(rawValue: rawValue) else {
            return .defaultValue
        }
        return OnlineASRSettings(selection: selection)
    }

    func save(_ settings: OnlineASRSettings) {
        defaults.set(settings.selection.rawValue, forKey: Self.key)
    }
}
