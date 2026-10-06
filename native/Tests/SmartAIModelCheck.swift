import Foundation

@main
struct SmartAIModelCheck {
    static func main() {
        precondition(SmartAIModel.defaultModel == .typeWhaleQwen3_4BInstruct)
        precondition(SmartAIModel.allCases.map(\.rawValue) == [
            "typewhale-qwen3-4b-instruct-2507-4bit",
            "deepseek-v4-flash",
        ])
        precondition(SmartAIModel.typeWhaleQwen3_4BInstruct.provider == .typeWhaleMLX)
        precondition(SmartAIModel.typeWhaleQwen3_4BInstruct.displayName == "本地直驱 Qwen3 4B Instruct")
        precondition(SmartAIModel.deepSeekV4Flash.provider == .deepSeek)
        precondition(!SmartAIModel.typeWhaleQwen3_4BInstruct.supportsUsageSummary)
        precondition(SmartAIModel.deepSeekV4Flash.supportsUsageSummary)
        precondition(SmartAIModel.fromStoredRawValue("MiniMax-M2") == .deepSeekV4Flash)
        precondition(
            SmartAIModel.fromStoredRawValue("Qwen3-4B-Instruct-2507-4bit")
                == .typeWhaleQwen3_4BInstruct
        )
        precondition(SmartAIModel.fromStoredRawValue("qwen3.5:2b-mlx") == nil)
        precondition(SmartAIModel.fromStoredRawValue("ollama-qwen3.6-35b-mlx") == nil)

        for model in SmartAIModel.allCases {
            precondition(SmartAIModel.fromMenuTag(model.menuTag) == model)
            precondition(!model.displayName.isEmpty)
        }

        verifyMigration(qwenReady: true, expectedFallback: .typeWhaleQwen3_4BInstruct)
        verifyMigration(qwenReady: false, expectedFallback: .deepSeekV4Flash)

        let suiteName = "SmartAIModelCheck.saved.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartAIModelStore(defaults: defaults, qwenReadiness: { false })
        store.save(.typeWhaleQwen3_4BInstruct)
        precondition(store.load() == .typeWhaleQwen3_4BInstruct)
        store.save(.deepSeekV4Flash)
        precondition(store.load() == .deepSeekV4Flash)

        print("SmartAIModelCheck passed")
    }

    private static func verifyMigration(
        qwenReady: Bool,
        expectedFallback: SmartAIModel
    ) {
        for legacyValue in [
            nil,
            "ollama-qwen3.5-2b-mlx",
            "ollama-qwen3.5-9b-mlx",
            "ollama-qwen3.6-35b-mlx",
            "ollama-qwen3.6-35b-rewrite",
            "unknown-model",
        ] as [String?] {
            let suiteName = "SmartAIModelCheck.migration.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("unable to create isolated defaults")
            }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            if let legacyValue {
                defaults.set(legacyValue, forKey: SmartAIModelStore.storageKey)
            }
            let store = SmartAIModelStore(
                defaults: defaults,
                qwenReadiness: { qwenReady }
            )
            precondition(store.load() == expectedFallback)
            precondition(
                defaults.string(forKey: SmartAIModelStore.storageKey)
                    == expectedFallback.rawValue
            )
        }
    }
}
