import Foundation

@main
struct ApplicationScopeLegacyBaselineCheck {
    static func main() {
        let key = "smartRewriteAutoConfiguration.v1"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        SmartRewriteAutoRuleStore.reset()
        let summary = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetAppName: "Xcode",
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "请总结今天的修改"
        )
        precondition(
            summary == .exhaustiveSummary,
            "content rule must keep priority over target application rule"
        )

        let development = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetAppName: "Xcode",
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "修复构建错误"
        )
        precondition(
            development == .developerRequirement,
            "existing Xcode target rule must remain developer requirement"
        )
        print("ApplicationScopeLegacyBaselineCheck passed")
    }
}
