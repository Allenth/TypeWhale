import Foundation

/// 用户可编辑的“社交窗口”清单：命中时中译英使用社交提示词，其余场景走常规提示词。
///
/// 每行一个关键词，小写后对目标 App 名 / Bundle ID / 窗口标题做子串匹配；`#` 开头的行视为注释。
enum SmartTranslationSocialScopeStore {
    private static let storageKey = "smartTranslationSocialScope"

    /// 内置默认社交清单（App 名与 Bundle ID 片段混合，命中即算社交窗口）。
    static let defaultKeywords: [String] = [
        "微信", "wechat",
        "qq",
        "微博", "weibo",
        "小红书", "xiaohongshu", "xingin",
        "threads",
        "twitter", "x.com",
        "discord",
        "telegram",
        "whatsapp",
        "instagram",
    ]

    static var defaultRawList: String {
        defaultKeywords.joined(separator: "\n")
    }

    static func rawList() -> String {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRawList : saved
    }

    static func save(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultRawList.trimmingCharacters(in: .whitespacesAndNewlines) {
            reset()
        } else {
            UserDefaults.standard.set(raw, forKey: storageKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func keywords() -> [String] {
        rawList()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 目标窗口是否属于社交清单：App 名 / Bundle ID / 窗口标题任一命中任一关键词。
    static func matches(_ context: SmartInputContext) -> Bool {
        let haystacks = [
            context.targetAppName,
            context.targetBundleIdentifier,
            context.windowTitle,
        ].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
        guard !haystacks.isEmpty else { return false }

        let keys = keywords()
        guard !keys.isEmpty else { return false }

        return keys.contains { key in
            haystacks.contains { $0.contains(key) }
        }
    }
}
