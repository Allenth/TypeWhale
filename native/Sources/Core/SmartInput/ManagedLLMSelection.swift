import Foundation

enum ManagedLLMModelID: String, CaseIterable, Codable {
    case qwen3_4BInstruct2507_4bit = "qwen3-4b-instruct-2507-4bit"
}

enum SmartAIEngineSelection: Equatable {
    case standard(SmartAIModel)
    case managed(ManagedLLMModelID)
}

struct ManagedLLMSelection: Equatable, Codable {
    var selectedModel: ManagedLLMModelID
    var isEnabled: Bool
    var returnModel: SmartAIModel

    static let defaultValue = ManagedLLMSelection(
        selectedModel: .qwen3_4BInstruct2507_4bit,
        isEnabled: false,
        returnModel: .deepSeekV4Flash
    )
}

struct ManagedLLMSelectionStore {
    static let storageKey = "managedLLM.selection"
    static let shared = ManagedLLMSelectionStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ManagedLLMSelection {
        guard let data = defaults.data(forKey: Self.storageKey),
              let selection = try? JSONDecoder().decode(ManagedLLMSelection.self, from: data) else {
            return .defaultValue
        }
        return selection
    }

    func save(_ selection: ManagedLLMSelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func retireLegacySelection() {
        let current = load()
        save(ManagedLLMSelection(
            selectedModel: .qwen3_4BInstruct2507_4bit,
            isEnabled: false,
            returnModel: current.returnModel
        ))
    }
}
