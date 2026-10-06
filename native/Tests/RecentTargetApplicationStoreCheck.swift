import Foundation

@main
struct RecentTargetApplicationStoreCheck {
    static func main() {
        let storageKey = RecentTargetApplicationStore.storageKey
        let original = UserDefaults.standard.data(forKey: storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        RecentTargetApplicationStore.reset()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        RecentTargetApplicationStore.record(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode",
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            usedAt: base
        )
        RecentTargetApplicationStore.record(
            bundleIdentifier: "com.tencent.xinWeChat",
            displayName: "微信",
            bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app"),
            usedAt: base.addingTimeInterval(10)
        )
        RecentTargetApplicationStore.record(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode",
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            usedAt: base.addingTimeInterval(20)
        )

        let deduplicated = RecentTargetApplicationStore.load()
        precondition(deduplicated.count == 2)
        precondition(deduplicated[0].bundleIdentifier == "com.apple.dt.Xcode")
        precondition(deduplicated[0].lastUsedAt == base.addingTimeInterval(20))
        precondition(deduplicated[1].bundleIdentifier == "com.tencent.xinWeChat")

        for index in 0..<25 {
            RecentTargetApplicationStore.record(
                bundleIdentifier: "com.example.app\(index)",
                displayName: "App \(index)",
                bundleURL: nil,
                usedAt: base.addingTimeInterval(Double(100 + index))
            )
        }
        let bounded = RecentTargetApplicationStore.load()
        precondition(
            bounded.count == RecentTargetApplicationStore.maximumRecordCount,
            "recent targets must stay bounded"
        )
        precondition(bounded[0].bundleIdentifier == "com.example.app24")
        precondition(
            Set(bounded.map(\.bundleIdentifier)).count == bounded.count,
            "recent targets must remain unique by bundle ID"
        )

        let beforeInvalidRecord = bounded
        RecentTargetApplicationStore.record(
            bundleIdentifier: "  ",
            displayName: "Invalid",
            bundleURL: nil,
            usedAt: base.addingTimeInterval(1_000)
        )
        precondition(
            RecentTargetApplicationStore.load() == beforeInvalidRecord,
            "empty bundle IDs must be ignored"
        )

        print("RecentTargetApplicationStoreCheck passed")
    }
}
