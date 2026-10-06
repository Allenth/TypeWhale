import Foundation

enum RewriteMode: String, CaseIterable, Codable {
    case raw
    case polish
    case developerRequirement
    case developerStatement
    case codeCommit
    case note
    case chat
    case exhaustiveSummary
    case command

    var displayName: String {
        switch self {
        case .raw: return "原文"
        case .polish: return "润色"
        case .developerRequirement: return "开发需求"
        case .developerStatement: return "开发需求版"
        case .codeCommit: return "代码提交版"
        case .note: return "即时归纳"
        case .chat: return "聊天"
        case .exhaustiveSummary: return "极致归纳"
        case .command: return "命令"
        }
    }
}

enum SmartRewritePreference: String, CaseIterable, Codable {
    case automatic
    case raw
    case polish
    case instantSummary
    case chat
    case developerRequirement
    case exhaustiveSummary

    static let allCases: [SmartRewritePreference] = [
        .automatic,
        .raw,
        .polish,
        .chat,
        .developerRequirement,
        .exhaustiveSummary,
    ]

    var displayName: String {
        switch self {
        case .automatic: return "自动"
        case .raw: return "原文"
        case .polish: return "润色"
        case .instantSummary: return "即时归纳"
        case .chat: return "聊天"
        case .developerRequirement: return "开发需求"
        case .exhaustiveSummary: return "极致归纳"
        }
    }

    var menuTag: Int {
        switch self {
        case .automatic: return 0
        case .raw: return 1
        case .polish: return 2
        case .instantSummary: return 6
        case .chat: return 3
        case .developerRequirement: return 4
        case .exhaustiveSummary: return 5
        }
    }

    var manualMode: RewriteMode? {
        switch self {
        case .automatic: return nil
        case .raw: return .raw
        case .polish: return .polish
        case .instantSummary: return .note
        case .chat: return .chat
        case .developerRequirement: return .developerRequirement
        case .exhaustiveSummary: return .exhaustiveSummary
        }
    }

    static func fromMenuTag(_ tag: Int) -> SmartRewritePreference {
        Self.allCases.first { $0.menuTag == tag } ?? .automatic
    }
}

struct RewriteProfile {
    let mode: RewriteMode
    let timeoutSeconds: TimeInterval

    var shouldRewrite: Bool {
        mode != .raw && mode != .command
    }
}

enum SmartRewriteShortUtterancePolicy {
    static func shouldBypassModel(
        text: String,
        mode: RewriteMode,
        preference: SmartRewritePreference
    ) -> Bool {
        guard mode == .exhaustiveSummary, preference == .exhaustiveSummary else {
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 24, !trimmed.contains("\n") else {
            return false
        }
        guard !trimmed.contains(where: { "，,、：:".contains($0) }) else {
            return false
        }
        let sentenceBreaks = trimmed.reduce(into: 0) { count, character in
            if "。！？!?；;".contains(character) {
                count += 1
            }
        }
        guard sentenceBreaks <= 1 else { return false }
        return !["第一", "第二", "第三", "最后", "步骤：", "要求："].contains {
            trimmed.contains($0)
        }
    }
}
