import Foundation

enum AutoSendSettingsStore {
    static let storageKey = "autoSendConfiguration.v1"

    static let defaultConfiguration = AutoSendConfiguration(
        isEnabled: false,
        actionsByBundleID: [:]
    )

    static func load() -> AutoSendConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configuration = try? JSONDecoder().decode(
                  AutoSendConfiguration.self,
                  from: data
              ) else {
            return defaultConfiguration
        }
        return normalized(configuration)
    }

    static func save(_ configuration: AutoSendConfiguration) {
        let value = normalized(configuration)
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func normalized(
        _ configuration: AutoSendConfiguration
    ) -> AutoSendConfiguration {
        let actions = configuration.actionsByBundleID.reduce(
            into: [String: PostPasteAction]()
        ) { result, pair in
            let bundleID = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, pair.value != .none else { return }
            result[bundleID] = pair.value
        }
        return AutoSendConfiguration(
            isEnabled: configuration.isEnabled,
            actionsByBundleID: actions,
            countdownSeconds: configuration.countdownSeconds
        )
    }
}
