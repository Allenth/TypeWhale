import AppKit

@main
enum ApplicationScopeEditorModelCheck {
    static func main() {
        verifyWindowSizing()
        verifyDraftIsolation()
        verifyEditorModelDoesNotPersistWhileEditing()
        verifyApplicationFiltering()
        verifyAdvancedRulesPaneRestoration()
        print("ApplicationScopeEditorModelCheck passed")
    }

    private static func verifyWindowSizing() {
        let small = ApplicationScopeWindowSizing.clampedContentSize(
            saved: NSSize(width: 1_400, height: 1_000),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 760)
        )
        precondition(small.width <= 1_152)
        precondition(small.height <= 684)

        let preferred = ApplicationScopeWindowSizing.clampedContentSize(
            saved: nil,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        precondition(preferred == NSSize(width: 960, height: 620))

        let undersizedScreen = ApplicationScopeWindowSizing.clampedContentSize(
            saved: NSSize(width: 960, height: 620),
            visibleFrame: NSRect(x: 0, y: 0, width: 760, height: 480)
        )
        precondition(undersizedScreen.width <= 684)
        precondition(undersizedScreen.height <= 432)
    }

    private static func verifyDraftIsolation() {
        let rewrite = SmartRewriteAutoConfiguration(
            rules: [],
            appModesByBundleID: [:],
            fallbackMode: .polish
        )
        let autoSend = AutoSendConfiguration(
            isEnabled: false,
            actionsByBundleID: [:]
        )
        var draft = ApplicationScopeDraft(
            rewriteConfiguration: rewrite,
            autoSendConfiguration: autoSend
        )

        draft.setRewriteMode(.chat, for: ["com.tencent.xinWeChat"])
        precondition(draft.autoSendConfiguration == autoSend)

        draft.setAutoSendAction(
            .returnKey,
            for: ["com.tencent.xinWeChat"]
        )
        precondition(
            draft.rewriteConfiguration
                .appModesByBundleID["com.tencent.xinWeChat"] == .chat
        )
        precondition(
            draft.autoSendConfiguration
                .actionsByBundleID["com.tencent.xinWeChat"] == .returnKey
        )

        draft.setAutoSendAction(.none, for: ["com.tencent.xinWeChat"])
        precondition(
            draft.autoSendConfiguration
                .actionsByBundleID["com.tencent.xinWeChat"] == nil
        )
    }

    private static func verifyEditorModelDoesNotPersistWhileEditing() {
        let original = ApplicationScopeDraft(
            rewriteConfiguration: SmartRewriteAutoConfiguration(
                rules: [],
                fallbackMode: .polish
            ),
            autoSendConfiguration: AutoSendConfiguration(
                isEnabled: false,
                actionsByBundleID: [:]
            )
        )
        var persisted: ApplicationScopeDraft?
        let model = ApplicationScopeEditorModel(
            initialSection: .rewrite,
            draft: original,
            persist: { persisted = $0 }
        )

        model.updateDraft {
            $0.setRewriteMode(.raw, for: ["com.apple.TextEdit"])
            $0.autoSendConfiguration.isEnabled = true
        }
        precondition(persisted == nil)
        precondition(model.draft != original)

        model.cancel()
        precondition(persisted == nil)
        precondition(model.draft == original)

        model.updateDraft {
            $0.setAutoSendAction(.commandReturn, for: ["com.openai.chat"])
        }
        model.save()
        precondition(persisted == model.draft)
    }

    private static func verifyApplicationFiltering() {
        let applications = [
            ApplicationCatalogItem(
                bundleIdentifier: "com.apple.dt.Xcode",
                displayName: "Xcode",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
                category: .development,
                lastUsedAt: nil
            ),
            ApplicationCatalogItem(
                bundleIdentifier: "com.tencent.xinWeChat",
                displayName: "微信",
                bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app"),
                category: .communication,
                lastUsedAt: Date()
            ),
            ApplicationCatalogItem(
                bundleIdentifier: "com.apple.TextEdit",
                displayName: "文本编辑",
                bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                category: .productivity,
                lastUsedAt: nil
            ),
        ]
        let draft = ApplicationScopeDraft(
            rewriteConfiguration: SmartRewriteAutoConfiguration(
                rules: [],
                appModesByBundleID: ["com.apple.dt.Xcode": .developerRequirement],
                fallbackMode: .polish
            ),
            autoSendConfiguration: AutoSendConfiguration(
                isEnabled: true,
                actionsByBundleID: ["com.tencent.xinWeChat": .returnKey]
            )
        )
        let model = ApplicationScopeEditorModel(
            initialSection: .rewrite,
            draft: draft,
            applications: applications,
            persist: { _ in }
        )

        model.query = "xcode"
        precondition(
            model.visibleApplications.map(\.bundleIdentifier)
                == ["com.apple.dt.Xcode"]
        )

        model.query = ""
        model.category = .communication
        precondition(
            model.visibleApplications.allSatisfy {
                $0.category == .communication
            }
        )

        model.category = .all
        model.showsConfiguredOnly = true
        precondition(model.visibleApplications.allSatisfy(model.isConfigured))
        precondition(
            model.visibleApplications.map(\.bundleIdentifier)
                == ["com.apple.dt.Xcode"]
        )

        model.selectedSection = .autoSend
        precondition(
            model.visibleApplications.map(\.bundleIdentifier)
                == ["com.tencent.xinWeChat"]
        )

        model.showsConfiguredOnly = false
        model.category = .recent
        precondition(
            model.visibleApplications.map(\.bundleIdentifier)
                == ["com.tencent.xinWeChat"]
        )
    }

    private static func verifyAdvancedRulesPaneRestoration() {
        let regular = ApplicationScopePaneSizing.restoredApplicationDividerPosition(
            totalWidth: 912,
            sidebarWidth: 125,
            previousApplicationWidth: 450,
            minimumDetailWidth: 260,
            dividerThickness: 1
        )
        precondition(regular == 576)

        let compact = ApplicationScopePaneSizing.restoredApplicationDividerPosition(
            totalWidth: 700,
            sidebarWidth: 125,
            previousApplicationWidth: 450,
            minimumDetailWidth: 260,
            dividerThickness: 1
        )
        precondition(compact == 439)
    }
}
