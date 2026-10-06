import Foundation

enum SmartAIProvider: String, Codable {
    case deepSeek
    case typeWhaleMLX

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .typeWhaleMLX: return "TypeWhale 本地直驱"
        }
    }
}

enum SmartAIModel: String, CaseIterable, Codable {
    case typeWhaleQwen3_4BInstruct = "typewhale-qwen3-4b-instruct-2507-4bit"
    case deepSeekV4Flash = "deepseek-v4-flash"

    static let defaultModel: SmartAIModel = .typeWhaleQwen3_4BInstruct

    var provider: SmartAIProvider {
        switch self {
        case .typeWhaleQwen3_4BInstruct: return .typeWhaleMLX
        case .deepSeekV4Flash: return .deepSeek
        }
    }

    var displayName: String {
        switch self {
        case .typeWhaleQwen3_4BInstruct: return "本地直驱 Qwen3 4B Instruct"
        case .deepSeekV4Flash: return "DeepSeek v4 flash"
        }
    }

    var engineModelName: String {
        switch self {
        case .typeWhaleQwen3_4BInstruct: return "qwen3-4b-instruct-2507-4bit"
        case .deepSeekV4Flash: return rawValue
        }
    }

    var menuTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var supportsUsageSummary: Bool {
        self == .deepSeekV4Flash
    }

    static func fromStoredRawValue(_ rawValue: String) -> SmartAIModel? {
        if let model = SmartAIModel(rawValue: rawValue) {
            return model
        }
        switch rawValue {
        case "MiniMax-M2", "MiniMax-M2.5-highspeed":
            return .deepSeekV4Flash
        case "Qwen3-4B-Instruct-2507-4bit":
            return .typeWhaleQwen3_4BInstruct
        default:
            return nil
        }
    }

    static func fromMenuTag(_ tag: Int) -> SmartAIModel {
        guard allCases.indices.contains(tag) else { return defaultModel }
        return allCases[tag]
    }
}

struct SmartAIModelStore {
    static let storageKey = "smartAIModel"

    private let defaults: UserDefaults
    private let qwenReadiness: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        qwenReadiness: @escaping () -> Bool = Self.defaultQwenReadiness
    ) {
        self.defaults = defaults
        self.qwenReadiness = qwenReadiness
    }

    func load() -> SmartAIModel {
        if let rawValue = defaults.string(forKey: Self.storageKey),
           let model = SmartAIModel.fromStoredRawValue(rawValue) {
            if rawValue != model.rawValue {
                save(model)
            }
            return model
        }

        let fallback: SmartAIModel = qwenReadiness()
            ? .typeWhaleQwen3_4BInstruct
            : .deepSeekV4Flash
        save(fallback)
        return fallback
    }

    func save(_ model: SmartAIModel) {
        defaults.set(model.rawValue, forKey: Self.storageKey)
    }

    static func load() -> SmartAIModel {
        SmartAIModelStore().load()
    }

    static func save(_ model: SmartAIModel) {
        SmartAIModelStore().save(model)
    }

    private static func defaultQwenReadiness() -> Bool {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }
        let supportRoot = applicationSupport
            .appendingPathComponent("TypeWhale Pro", isDirectory: true)
        let modelRoot = supportRoot
            .appendingPathComponent("Models/LLM/qwen3-4b-instruct-2507-4bit", isDirectory: true)
        let requiredModelFiles = [
            "config.json",
            "model.safetensors",
            "tokenizer.json",
            "tokenizer_config.json",
        ]
        guard requiredModelFiles.allSatisfy({
            fileManager.fileExists(atPath: modelRoot.appendingPathComponent($0).path)
        }) else {
            return false
        }

        let runtimesRoot = supportRoot.appendingPathComponent("Runtimes", isDirectory: true)
        return [
            "mlx-llm/v1/python/bin/python3",
            "mlx-llm/v1/python/bin/python3.10",
            "mlx-asr/v1/python/bin/python3",
            "mlx-asr/v1/python/bin/python3.10",
        ].contains {
            fileManager.isExecutableFile(
                atPath: runtimesRoot.appendingPathComponent($0).path
            )
        }
    }
}
