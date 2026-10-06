import AppKit

enum ApplicationScopeSection: Equatable {
    case rewrite
    case autoSend
}

struct ApplicationScopeDraft: Equatable {
    var rewriteConfiguration: SmartRewriteAutoConfiguration
    var autoSendConfiguration: AutoSendConfiguration

    mutating func setRewriteMode(
        _ mode: RewriteMode?,
        for bundleIdentifiers: [String]
    ) {
        for bundleIdentifier in normalized(bundleIdentifiers) {
            if let mode {
                rewriteConfiguration.appModesByBundleID[bundleIdentifier] = mode
            } else {
                rewriteConfiguration.appModesByBundleID.removeValue(
                    forKey: bundleIdentifier
                )
            }
        }
    }

    mutating func setAutoSendAction(
        _ action: PostPasteAction,
        for bundleIdentifiers: [String]
    ) {
        for bundleIdentifier in normalized(bundleIdentifiers) {
            if action == .none {
                autoSendConfiguration.actionsByBundleID.removeValue(
                    forKey: bundleIdentifier
                )
            } else {
                autoSendConfiguration.actionsByBundleID[bundleIdentifier] = action
            }
        }
    }

    private func normalized(_ bundleIdentifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return bundleIdentifiers.compactMap { value in
            let normalized = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }
}

final class ApplicationScopeEditorModel {
    private let originalDraft: ApplicationScopeDraft
    private let persist: (ApplicationScopeDraft) -> Void

    private(set) var draft: ApplicationScopeDraft
    var selectedSection: ApplicationScopeSection
    var query = ""
    var category: ApplicationCategory = .all
    var showsConfiguredOnly = false
    var selectedBundleIdentifiers: Set<String> = []
    private(set) var applications: [ApplicationCatalogItem]

    init(
        initialSection: ApplicationScopeSection,
        draft: ApplicationScopeDraft,
        applications: [ApplicationCatalogItem] = [],
        persist: @escaping (ApplicationScopeDraft) -> Void
    ) {
        selectedSection = initialSection
        originalDraft = draft
        self.draft = draft
        self.applications = applications
        self.persist = persist
    }

    var visibleApplications: [ApplicationCatalogItem] {
        applications.filter { item in
            let matchesCategory: Bool
            switch category {
            case .all:
                matchesCategory = true
            case .recent:
                matchesCategory = item.lastUsedAt != nil
            default:
                matchesCategory = item.category == category
            }
            let normalizedQuery = query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let matchesQuery = normalizedQuery.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(
                    normalizedQuery
                )
                || item.bundleIdentifier.localizedCaseInsensitiveContains(
                    normalizedQuery
                )
            return matchesCategory
                && matchesQuery
                && (!showsConfiguredOnly || isConfigured(item))
        }
    }

    func setApplications(_ applications: [ApplicationCatalogItem]) {
        self.applications = applications
        let knownBundleIdentifiers = Set(
            applications.map(\.bundleIdentifier)
        )
        selectedBundleIdentifiers.formIntersection(knownBundleIdentifiers)
    }

    func isConfigured(_ item: ApplicationCatalogItem) -> Bool {
        switch selectedSection {
        case .rewrite:
            return draft.rewriteConfiguration
                .appModesByBundleID[item.bundleIdentifier] != nil
        case .autoSend:
            return draft.autoSendConfiguration
                .actionsByBundleID[item.bundleIdentifier] != nil
        }
    }

    func valueText(for item: ApplicationCatalogItem) -> String {
        switch selectedSection {
        case .rewrite:
            return draft.rewriteConfiguration
                .appModesByBundleID[item.bundleIdentifier]?.displayName
                ?? "未指定"
        case .autoSend:
            switch draft.autoSendConfiguration
                .actionsByBundleID[item.bundleIdentifier] ?? .none {
            case .none:
                return "关闭"
            case .returnKey:
                return "回车"
            case .commandReturn:
                return "⌘ 回车"
            }
        }
    }

    func updateDraft(_ update: (inout ApplicationScopeDraft) -> Void) {
        update(&draft)
    }

    func save() {
        persist(draft)
    }

    func cancel() {
        draft = originalDraft
    }
}

enum ApplicationScopeWindowSizing {
    static let preferredContentSize = NSSize(width: 960, height: 620)
    static let minimumContentSize = NSSize(width: 820, height: 520)
    private static let visibleFrameRatio = 0.9

    static func clampedContentSize(
        saved: NSSize?,
        visibleFrame: NSRect
    ) -> NSSize {
        let maximum = NSSize(
            width: max(1, visibleFrame.width * visibleFrameRatio),
            height: max(1, visibleFrame.height * visibleFrameRatio)
        )
        let minimum = NSSize(
            width: min(minimumContentSize.width, maximum.width),
            height: min(minimumContentSize.height, maximum.height)
        )
        let candidate = saved ?? preferredContentSize
        return NSSize(
            width: min(max(candidate.width, minimum.width), maximum.width),
            height: min(max(candidate.height, minimum.height), maximum.height)
        )
    }
}

enum ApplicationScopePaneSizing {
    static func restoredApplicationDividerPosition(
        totalWidth: CGFloat,
        sidebarWidth: CGFloat,
        previousApplicationWidth: CGFloat,
        minimumDetailWidth: CGFloat,
        dividerThickness: CGFloat
    ) -> CGFloat {
        let minimumApplicationWidth: CGFloat = 260
        let minimumPosition = sidebarWidth
            + dividerThickness
            + minimumApplicationWidth
        let desiredPosition = sidebarWidth
            + dividerThickness
            + max(previousApplicationWidth, minimumApplicationWidth)
        let maximumPosition = totalWidth
            - minimumDetailWidth
            - dividerThickness
        return min(max(desiredPosition, minimumPosition), maximumPosition)
    }
}
