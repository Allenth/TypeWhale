import Foundation

enum RewriteMode: String, CaseIterable, Codable {
    case raw
    case polish
    case developerRequirement
    case note
    case chat
    case exhaustiveSummary
    case command

    var displayName: String {
        switch self {
        case .raw: return "原文"
        case .polish: return "润色"
        case .developerRequirement: return "开发需求"
        case .note: return "笔记"
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
    case developerRequirement
    case exhaustiveSummary

    var displayName: String {
        switch self {
        case .automatic: return "自动"
        case .raw: return "原文"
        case .polish: return "润色"
        case .developerRequirement: return "开发需求"
        case .exhaustiveSummary: return "极致归纳"
        }
    }

    var menuTag: Int {
        switch self {
        case .automatic: return 0
        case .raw: return 1
        case .polish: return 2
        case .developerRequirement: return 3
        case .exhaustiveSummary: return 4
        }
    }

    var manualMode: RewriteMode? {
        switch self {
        case .automatic: return nil
        case .raw: return .raw
        case .polish: return .polish
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
