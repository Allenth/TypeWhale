import Foundation

enum ApplicationCategory: String, CaseIterable {
    case recent
    case communication
    case productivity
    case development
    case browser
    case other
    case all
}

struct InstalledApplicationMetadata: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let categoryIdentifier: String?
}

struct ApplicationCatalogItem: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let category: ApplicationCategory
    let lastUsedAt: Date?
}

@MainActor
protocol ApplicationCatalogLoading: AnyObject {
    func load() async -> [ApplicationCatalogItem]
    func cancel()
}

@MainActor
final class ApplicationCatalog: ApplicationCatalogLoading {
    typealias InstalledLoader = () -> [InstalledApplicationMetadata]
    typealias RecentLoader = () -> [RecentTargetApplicationRecord]

    private let installedLoader: InstalledLoader
    private let recentLoader: RecentLoader
    private var loadTask: Task<[ApplicationCatalogItem], Never>?
    private var loadGeneration: UUID?

    convenience init() {
        self.init(
            installedLoader: Self.scanInstalledApplications,
            recentLoader: RecentTargetApplicationStore.load
        )
    }

    init(
        installedLoader: @escaping InstalledLoader,
        recentLoader: @escaping RecentLoader
    ) {
        self.installedLoader = installedLoader
        self.recentLoader = recentLoader
    }

    func load() async -> [ApplicationCatalogItem] {
        let installedLoader = self.installedLoader
        let recentLoader = self.recentLoader
        let generation = UUID()
        let task = Task.detached(priority: .utility) {
            () -> [ApplicationCatalogItem] in
            guard !Task.isCancelled else { return [] }
            let installed = installedLoader()
            guard !Task.isCancelled else { return [] }
            return Self.merge(
                installed: installed,
                recent: recentLoader()
            )
        }
        loadTask?.cancel()
        loadTask = task
        loadGeneration = generation
        let result = await task.value
        if loadGeneration == generation {
            loadTask = nil
            loadGeneration = nil
        }
        return result
    }

    func cancel() {
        let task = loadTask
        loadTask = nil
        loadGeneration = nil
        task?.cancel()
    }

    nonisolated private static func scanInstalledApplications() -> [InstalledApplicationMetadata] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        var applications: [InstalledApplicationMetadata] = []
        for root in roots {
            guard !Task.isCancelled else { break }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else {
                    enumerator.skipDescendants()
                    break
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let metadata = metadata(for: url) else { continue }
                applications.append(metadata)
            }
        }
        return applications
    }

    nonisolated private static func metadata(
        for applicationURL: URL
    ) -> InstalledApplicationMetadata? {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }
        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let categoryIdentifier = bundle.object(
            forInfoDictionaryKey: "LSApplicationCategoryType"
        ) as? String
        return InstalledApplicationMetadata(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: applicationURL,
            categoryIdentifier: categoryIdentifier
        )
    }

    nonisolated private static func merge(
        installed: [InstalledApplicationMetadata],
        recent: [RecentTargetApplicationRecord]
    ) -> [ApplicationCatalogItem] {
        let recentByBundleID = Dictionary(
            uniqueKeysWithValues: recent.map { ($0.bundleIdentifier, $0) }
        )
        var seen = Set<String>()
        var items = installed.compactMap { metadata -> ApplicationCatalogItem? in
            guard !Task.isCancelled else { return nil }
            let bundleID = metadata.bundleIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !bundleID.isEmpty, seen.insert(bundleID).inserted else {
                return nil
            }
            return ApplicationCatalogItem(
                bundleIdentifier: bundleID,
                displayName: metadata.displayName,
                bundleURL: metadata.bundleURL,
                category: category(
                    bundleIdentifier: bundleID,
                    displayName: metadata.displayName,
                    categoryIdentifier: metadata.categoryIdentifier
                ),
                lastUsedAt: recentByBundleID[bundleID]?.lastUsedAt
            )
        }
        for record in recent {
            guard !Task.isCancelled,
                  let bundleURL = record.bundleURL,
                  seen.insert(record.bundleIdentifier).inserted else {
                continue
            }
            items.append(ApplicationCatalogItem(
                bundleIdentifier: record.bundleIdentifier,
                displayName: record.displayName,
                bundleURL: bundleURL,
                category: category(
                    bundleIdentifier: record.bundleIdentifier,
                    displayName: record.displayName,
                    categoryIdentifier: nil
                ),
                lastUsedAt: record.lastUsedAt
            ))
        }
        return items.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.displayName.localizedStandardCompare(
                    rhs.displayName
                ) == .orderedAscending
            }
        }
    }

    nonisolated private static func category(
        bundleIdentifier: String,
        displayName: String,
        categoryIdentifier: String?
    ) -> ApplicationCategory {
        let category = categoryIdentifier?.lowercased() ?? ""
        if category.contains("developer-tools") {
            return .development
        }
        if category.contains("social-networking") ||
            category.contains("video") {
            return .communication
        }
        if category.contains("business") ||
            category.contains("productivity") ||
            category.contains("finance") ||
            category.contains("education") {
            return .productivity
        }

        let haystack = "\(bundleIdentifier) \(displayName)".lowercased()
        let browserKeywords = [
            "safari", "chrome", "firefox", "edge", "brave",
            "arc", "opera", "vivaldi", "dia",
        ]
        if browserKeywords.contains(where: haystack.contains) {
            return .browser
        }
        let communicationKeywords = [
            "wechat", "weixin", "xinwechat", "messages", "slack",
            "discord", "telegram", "whatsapp", "teams", "zoom",
            "feishu", "lark", "dingtalk", "qq",
        ]
        if communicationKeywords.contains(where: haystack.contains) {
            return .communication
        }
        let developmentKeywords = [
            "xcode", "cursor", "visual studio", "vscode", "terminal",
            "iterm", "warp", "codex", "claude",
        ]
        if developmentKeywords.contains(where: haystack.contains) {
            return .development
        }
        return .other
    }
}
