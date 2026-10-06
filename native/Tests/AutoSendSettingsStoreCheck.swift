import Foundation

@main
struct AutoSendSettingsStoreCheck {
    static func main() {
        let storageKey = AutoSendSettingsStore.storageKey
        let original = UserDefaults.standard.data(forKey: storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        AutoSendSettingsStore.reset()
        precondition(
            AutoSendSettingsStore.load() == .init(
                isEnabled: false,
                actionsByBundleID: [:],
                countdownSeconds: 2
            ),
            "auto-send must default to disabled with no app actions and a two-second countdown"
        )

        AutoSendSettingsStore.save(.init(
            isEnabled: true,
            actionsByBundleID: [
                " com.tencent.xinWeChat ": .returnKey,
                "com.apple.dt.Xcode": .commandReturn,
                "": .returnKey,
                "com.example.none": .none,
            ],
            countdownSeconds: 0
        ))
        precondition(
            AutoSendSettingsStore.load() == .init(
                isEnabled: true,
                actionsByBundleID: [
                    "com.tencent.xinWeChat": .returnKey,
                    "com.apple.dt.Xcode": .commandReturn,
                ],
                countdownSeconds: 1
            ),
            "save must normalize actions and clamp countdowns below one second"
        )

        let futureJSON = """
        {
          "isEnabled": true,
          "actionsByBundleID": {
            "com.tencent.xinWeChat": "returnKey",
            "com.example.future": "futureAction"
          }
        }
        """.data(using: .utf8)!
        UserDefaults.standard.set(futureJSON, forKey: storageKey)
        precondition(
            AutoSendSettingsStore.load() == .init(
                isEnabled: true,
                actionsByBundleID: [
                    "com.tencent.xinWeChat": .returnKey,
                ],
                countdownSeconds: 2
            ),
            "legacy configuration must default to a two-second countdown"
        )

        AutoSendSettingsStore.save(.init(
            isEnabled: true,
            actionsByBundleID: [:],
            countdownSeconds: 11
        ))
        precondition(
            AutoSendSettingsStore.load().countdownSeconds == 10,
            "countdowns above ten seconds must clamp to ten"
        )

        print("AutoSendSettingsStoreCheck passed")
    }
}
