import Foundation

@main
struct OnlineASRSettingsCheck {
    static func main() {
        let suite = "OnlineASRSettingsCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let store = OnlineASRSettingsStore(defaults: defaults)
        precondition(store.load().selection == .off)
        store.save(OnlineASRSettings(selection: .doubao))
        precondition(store.load().selection == .doubao)
        store.save(OnlineASRSettings(selection: .mimoV25))
        precondition(store.load().selection == .mimoV25)
        precondition(defaults.string(forKey: "onlineASRProviderSelection") == "mimoV25")

        defaults.set("removed-provider", forKey: "onlineASRProviderSelection")
        precondition(store.load().selection == .off)
        print("OnlineASRSettingsCheck passed")
    }
}
