import Foundation

enum DeveloperTermCategory: String, CaseIterable, Codable {
    case tool
    case model
    case framework
    case language
    case api
    case product
    case project
    case acronym

    var displayName: String {
        switch self {
        case .tool: return "工具"
        case .model: return "模型"
        case .framework: return "框架"
        case .language: return "语言"
        case .api: return "API"
        case .product: return "产品"
        case .project: return "项目"
        case .acronym: return "缩写"
        }
    }
}

struct DeveloperTerm: Codable, Equatable, Identifiable {
    var id: UUID
    var canonical: String
    var aliases: [String]
    var category: DeveloperTermCategory
    var caseSensitive: Bool

    init(
        id: UUID = UUID(),
        canonical: String,
        aliases: [String],
        category: DeveloperTermCategory,
        caseSensitive: Bool = false
    ) {
        self.id = id
        self.canonical = canonical
        self.aliases = aliases
        self.category = category
        self.caseSensitive = caseSensitive
    }
}

struct DeveloperTermReplacement: Codable, Equatable {
    let original: String
    let canonical: String
}

struct DeveloperTermNormalizationResult: Equatable {
    let text: String
    let replacements: [DeveloperTermReplacement]
}
