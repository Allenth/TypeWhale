import Foundation

@main
struct ManagedLLMSelectionCheck {
    static func main() throws {
        let suiteName = "ManagedLLMSelectionCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ManagedLLMSelectionStore(defaults: defaults)
        precondition(store.load() == ManagedLLMSelection(
            selectedModel: .qwen3_4BInstruct2507_4bit,
            isEnabled: false,
            returnModel: .deepSeekV4Flash
        ))
        precondition(
            SmartAIEngineSelection.standard(.deepSeekV4Flash)
                != .managed(.qwen3_4BInstruct2507_4bit)
        )

        let enabled = ManagedLLMSelection(
            selectedModel: .qwen3_4BInstruct2507_4bit,
            isEnabled: true,
            returnModel: .deepSeekV4Flash
        )
        store.save(enabled)
        precondition(store.load() == enabled)
        store.retireLegacySelection()
        precondition(store.load() == ManagedLLMSelection(
            selectedModel: .qwen3_4BInstruct2507_4bit,
            isEnabled: false,
            returnModel: .deepSeekV4Flash
        ))

        defaults.set(Data("not-json".utf8), forKey: ManagedLLMSelectionStore.storageKey)
        precondition(store.load().isEnabled == false)
        precondition(store.load().returnModel == .deepSeekV4Flash)

        print("ManagedLLMSelectionCheck passed")
    }
}
