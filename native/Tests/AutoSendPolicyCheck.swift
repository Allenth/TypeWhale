import Foundation

@main
struct AutoSendPolicyCheck {
    static func main() {
        let policy = AutoSendPolicy()
        let enabled = AutoSendConfiguration(
            isEnabled: true,
            actionsByBundleID: [
                "com.tencent.xinWeChat": .returnKey,
                "com.apple.dt.Xcode": .commandReturn,
            ]
        )

        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: "你好",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: false
            ),
            equals: .returnKey,
            "configured ordinary dictation should return the app action"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: "提交代码",
                targetBundleIdentifier: "com.apple.dt.Xcode",
                isTranslated: false
            ),
            equals: .commandReturn,
            "configured command-return app should keep its exact action"
        )

        var disabled = enabled
        disabled.isEnabled = false
        assertAction(
            policy.action(
                configuration: disabled,
                purpose: .dictation,
                text: "你好",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: false
            ),
            equals: .none,
            "global switch off must suppress every action"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .ideaPill,
                text: "你好",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: false
            ),
            equals: .none,
            "idea pill must never auto-send"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .openClawChat,
                text: "你好",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: false
            ),
            equals: .none,
            "OpenClaw must never auto-send"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: "Hello",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: true
            ),
            equals: .none,
            "translated output must never auto-send"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: " \n ",
                targetBundleIdentifier: "com.tencent.xinWeChat",
                isTranslated: false
            ),
            equals: .none,
            "empty text must never auto-send"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: "你好",
                targetBundleIdentifier: nil,
                isTranslated: false
            ),
            equals: .none,
            "missing target must never auto-send"
        )
        assertAction(
            policy.action(
                configuration: enabled,
                purpose: .dictation,
                text: "你好",
                targetBundleIdentifier: "com.apple.Notes",
                isTranslated: false
            ),
            equals: .none,
            "unconfigured app must only paste"
        )

        print("AutoSendPolicyCheck passed")
    }

    private static func assertAction(
        _ actual: PostPasteAction,
        equals expected: PostPasteAction,
        _ message: String
    ) {
        precondition(actual == expected, "\(message): expected \(expected), got \(actual)")
    }
}
