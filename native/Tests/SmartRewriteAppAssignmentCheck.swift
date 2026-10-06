import Foundation

@main
struct SmartRewriteAppAssignmentCheck {
    static func main() {
        let storageKey = "smartRewriteAutoConfiguration.v1"
        let original = UserDefaults.standard.data(forKey: storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        let summaryRule = SmartRewriteAutoRule(
            id: "summary",
            title: "总结",
            keywords: ["总结"],
            mode: .exhaustiveSummary,
            isEnabled: true,
            matchTarget: false,
            matchContent: true
        )
        SmartRewriteAutoRuleStore.save(SmartRewriteAutoConfiguration(
            rules: [summaryRule],
            appModesByBundleID: [
                "com.apple.dt.Xcode": .developerRequirement,
                "": .chat,
                "com.example.unsupported": .command,
            ],
            fallbackMode: .polish
        ))

        let loaded = SmartRewriteAutoRuleStore.load()
        precondition(
            loaded.appModesByBundleID == [
                "com.apple.dt.Xcode": .developerRequirement,
            ],
            "save must drop empty bundle IDs and unsupported modes"
        )

        let summary = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "总结修改"
        )
        precondition(
            summary == .exhaustiveSummary,
            "advanced content rules must keep priority over app defaults"
        )

        let appDefault = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "修复错误"
        )
        precondition(
            appDefault == .developerRequirement,
            "exact bundle ID should use its app default"
        )

        let fallback = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetBundleIdentifier: "com.apple.Notes"
            ),
            rawText: "普通记录"
        )
        precondition(fallback == .polish, "unassigned apps must use fallback")

        let legacyJSON = """
        {
          "rules": [
            {
              "id": "legacy-first",
              "title": "旧规则一",
              "keywords": ["first"],
              "mode": "chat",
              "isEnabled": true,
              "matchTarget": true,
              "matchContent": false
            },
            {
              "id": "legacy-second",
              "title": "旧规则二",
              "keywords": ["second"],
              "mode": "polish",
              "isEnabled": true,
              "matchTarget": true,
              "matchContent": false
            }
          ],
          "fallbackMode": "chat"
        }
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacyJSON, forKey: storageKey)
        let migrated = SmartRewriteAutoRuleStore.load()
        precondition(
            migrated.appModesByBundleID.isEmpty,
            "legacy JSON without app defaults must decode to an empty map"
        )
        let customIDs = migrated.rules
            .filter { $0.id.hasPrefix("legacy-") }
            .map(\.id)
        precondition(
            customIDs == ["legacy-first", "legacy-second"],
            "legacy custom rule order must remain unchanged"
        )
        precondition(migrated.fallbackMode == .chat)

        print("SmartRewriteAppAssignmentCheck passed")
    }
}
