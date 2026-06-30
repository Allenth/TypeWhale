import Foundation

enum SmartAIProvider: String, Codable {
    case deepSeek

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        }
    }
}

enum SmartAIModel: String, CaseIterable, Codable {
    case deepSeekV4Flash = "deepseek-v4-flash"

    static let defaultModel: SmartAIModel = .deepSeekV4Flash

    var provider: SmartAIProvider {
        switch self {
        case .deepSeekV4Flash: return .deepSeek
        }
    }

    var displayName: String {
        switch self {
        case .deepSeekV4Flash: return "DeepSeek v4 flash"
        }
    }

    var menuTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var supportsUsageSummary: Bool {
        switch self {
        case .deepSeekV4Flash:
            return true
        }
    }

    static func fromStoredRawValue(_ rawValue: String) -> SmartAIModel? {
        if let model = SmartAIModel(rawValue: rawValue) {
            return model
        }
        switch rawValue {
        case "MiniMax-M2", "MiniMax-M2.5-highspeed":
            return .deepSeekV4Flash
        default:
            return nil
        }
    }

    static func fromMenuTag(_ tag: Int) -> SmartAIModel {
        guard allCases.indices.contains(tag) else { return defaultModel }
        return allCases[tag]
    }
}

enum SmartAIModelStore {
    private static let storageKey = "smartAIModel"

    static func load() -> SmartAIModel {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let model = SmartAIModel.fromStoredRawValue(rawValue) else {
            return SmartAIModel.defaultModel
        }
        if rawValue != model.rawValue {
            save(model)
        }
        return model
    }

    static func save(_ model: SmartAIModel) {
        UserDefaults.standard.set(model.rawValue, forKey: storageKey)
    }
}
