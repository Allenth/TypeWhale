import Foundation

enum SmartAIProvider: String, Codable {
    case deepSeek
    case ollama

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .ollama: return "Ollama"
        }
    }
}

enum SmartAIModel: String, CaseIterable, Codable {
    case ollamaQwen35B = "ollama-qwen3.6-35b-mlx"
    case ollamaQwen8B = "ollama-qwen3-8b"
    case deepSeekV4Flash = "deepseek-v4-flash"

    static let defaultModel: SmartAIModel = .ollamaQwen35B

    var provider: SmartAIProvider {
        switch self {
        case .ollamaQwen35B, .ollamaQwen8B: return .ollama
        case .deepSeekV4Flash: return .deepSeek
        }
    }

    var displayName: String {
        switch self {
        case .ollamaQwen35B: return "本地 Qwen3.6 35B"
        case .ollamaQwen8B: return "本地 Qwen3 8B"
        case .deepSeekV4Flash: return "DeepSeek v4 flash"
        }
    }

    var engineModelName: String {
        switch self {
        case .ollamaQwen35B: return "qwen3.6:35b-mlx"
        case .ollamaQwen8B: return "qwen3:8b"
        case .deepSeekV4Flash: return rawValue
        }
    }

    var menuTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var supportsUsageSummary: Bool {
        switch self {
        case .ollamaQwen35B, .ollamaQwen8B:
            return false
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
        case "qwen3.6:35b-mlx", "Qwen3.6-35B-A3B-MLX-8bit":
            return .ollamaQwen35B
        case "qwen3:8b", "Qwen3-8B":
            return .ollamaQwen8B
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
