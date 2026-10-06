import Foundation

@main
struct TTSLabRuntimeReadinessStoreCheck {
    static func main() throws {
        let suite = "TTSLabRuntimeReadinessStoreCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("unable to create isolated defaults")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let store = TTSLabRuntimeReadinessStore(defaults: defaults)
        precondition(
            store.load(modelID: "qwen-06b", runtimeFingerprint: "coreml-v1")
                == .unknown
        )

        store.save(
            .ready,
            modelID: "qwen-06b",
            runtimeFingerprint: "coreml-v1"
        )
        precondition(
            store.load(modelID: "qwen-06b", runtimeFingerprint: "coreml-v1")
                == .ready
        )
        precondition(
            store.load(modelID: "qwen-06b", runtimeFingerprint: "coreml-v2")
                == .unknown
        )
        precondition(
            store.load(modelID: "qwen-17b", runtimeFingerprint: "coreml-v1")
                == .unknown
        )

        let model = TTSLabModel(
            id: "qwen-06b",
            displayName: "Qwen 0.6B",
            tier: 1,
            runtime: .ttsKit,
            capabilities: .basic,
            directory: FileManager.default.temporaryDirectory,
            qualification: .unverified,
            weightState: .installed,
            runtimeReadiness: .ready
        )
        precondition(model.weightState == .installed)
        precondition(model.runtimeReadiness == .ready)

        print("TTSLabRuntimeReadinessStoreCheck passed")
    }
}
