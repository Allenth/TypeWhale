import Foundation

struct SmartRewriteAutoRule: Codable, Equatable {
    var id: String
    var title: String
    var keywords: [String]
    var mode: RewriteMode
    var isEnabled: Bool
    var matchTarget: Bool
    var matchContent: Bool

    init(
        id: String,
        title: String,
        keywords: [String],
        mode: RewriteMode,
        isEnabled: Bool,
        matchTarget: Bool = true,
        matchContent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.mode = mode
        self.isEnabled = isEnabled
        self.matchTarget = matchTarget
        self.matchContent = matchContent
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case keywords
        case mode
        case isEnabled
        case matchTarget
        case matchContent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        keywords = try container.decode([String].self, forKey: .keywords)
        mode = try container.decode(RewriteMode.self, forKey: .mode)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        matchTarget = try container.decodeIfPresent(Bool.self, forKey: .matchTarget) ?? true
        matchContent = try container.decodeIfPresent(Bool.self, forKey: .matchContent) ?? false
    }

    var keywordText: String {
        get { keywords.joined(separator: ", ") }
        set {
            keywords = newValue
                .split { $0 == "," || $0 == "\n" || $0 == "，" }
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}

struct SmartRewriteAutoConfiguration: Codable, Equatable {
    var rules: [SmartRewriteAutoRule]
    var fallbackMode: RewriteMode
}

enum SmartRewriteAutoRuleStore {
    private static let storageKey = "smartRewriteAutoConfiguration.v1"

    static let selectableModes: [RewriteMode] = [
        .polish,
        .developerRequirement,
        .note,
        .chat,
        .exhaustiveSummary,
        .raw,
    ]

    static var defaultConfiguration: SmartRewriteAutoConfiguration {
        SmartRewriteAutoConfiguration(
            rules: [
                SmartRewriteAutoRule(
                    id: "summary-intent",
                    title: "总结归纳口述",
                    keywords: ["总结", "归纳", "要点", "会议纪要", "行动项", "复盘", "summary", "summarize"],
                    mode: .exhaustiveSummary,
                    isEnabled: true,
                    matchTarget: false,
                    matchContent: true
                ),
                SmartRewriteAutoRule(
                    id: "ai-dev",
                    title: "AI 编程窗口",
                    keywords: ["codex", "cursor", "claude", "chatgpt", "com.openai.chat"],
                    mode: .developerRequirement,
                    isEnabled: true
                ),
                SmartRewriteAutoRule(
                    id: "terminal-dev",
                    title: "终端与代码编辑器",
                    keywords: ["terminal", "iterm", "warp", "code", "xcode", "visual studio"],
                    mode: .developerRequirement,
                    isEnabled: true
                ),
                SmartRewriteAutoRule(
                    id: "notes",
                    title: "笔记窗口",
                    keywords: ["obsidian", "notion", "notes"],
                    mode: .note,
                    isEnabled: true
                ),
                SmartRewriteAutoRule(
                    id: "chat",
                    title: "聊天窗口",
                    keywords: ["wechat", "telegram", "messages", "com.apple.mobilesms"],
                    mode: .chat,
                    isEnabled: true
                ),
            ],
            fallbackMode: .polish
        )
    }

    static func load() -> SmartRewriteAutoConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(SmartRewriteAutoConfiguration.self, from: data) else {
            return defaultConfiguration
        }
        return mergedWithDefaults(decoded)
    }

    static func save(_ configuration: SmartRewriteAutoConfiguration) {
        let normalized = SmartRewriteAutoConfiguration(
            rules: configuration.rules.map { rule in
                SmartRewriteAutoRule(
                    id: rule.id,
                    title: rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "未命名范围"
                        : rule.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    keywords: rule.keywords
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty },
                    mode: selectableModes.contains(rule.mode) ? rule.mode : .polish,
                    isEnabled: rule.isEnabled,
                    matchTarget: rule.matchTarget,
                    matchContent: rule.matchContent
                )
            },
            fallbackMode: selectableModes.contains(configuration.fallbackMode) ? configuration.fallbackMode : .polish
        )
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func mode(for context: SmartInputContext, rawText: String = "") -> RewriteMode {
        let configuration = load()
        let targetHaystack = [context.targetAppName, context.targetBundleIdentifier, context.windowTitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let contentHaystack = rawText.lowercased()
        for rule in configuration.rules where rule.isEnabled {
            let keywords = rule.keywords.map { $0.lowercased() }
            let matchesTarget = rule.matchTarget && keywords.contains {
                !($0.isEmpty) && targetHaystack.contains($0)
            }
            let matchesContent = rule.matchContent && keywords.contains {
                !($0.isEmpty) && contentHaystack.contains($0)
            }
            if matchesTarget || matchesContent {
                return rule.mode
            }
        }
        return configuration.fallbackMode
    }

    private static func mergedWithDefaults(_ configuration: SmartRewriteAutoConfiguration) -> SmartRewriteAutoConfiguration {
        var rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })
        for defaultRule in defaultConfiguration.rules where rulesByID[defaultRule.id] == nil {
            rulesByID[defaultRule.id] = defaultRule
        }
        let orderedRules = defaultConfiguration.rules.compactMap { rulesByID[$0.id] }
        let customRules = configuration.rules.filter { rule in
            !defaultConfiguration.rules.contains { $0.id == rule.id }
        }
        return SmartRewriteAutoConfiguration(
            rules: orderedRules + customRules,
            fallbackMode: selectableModes.contains(configuration.fallbackMode) ? configuration.fallbackMode : .polish
        )
    }
}
