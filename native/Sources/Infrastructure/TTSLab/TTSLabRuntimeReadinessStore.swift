import Foundation

final class TTSLabRuntimeReadinessStore {
    private let defaults: UserDefaults
    private let prefix = "tts.lab.runtime.readiness"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(
        modelID: String,
        runtimeFingerprint: String
    ) -> TTSLabRuntimeReadiness {
        guard let rawValue = defaults.string(
            forKey: key(modelID: modelID, runtimeFingerprint: runtimeFingerprint)
        ) else {
            return .unknown
        }
        return TTSLabRuntimeReadiness(rawValue: rawValue) ?? .unknown
    }

    func save(
        _ readiness: TTSLabRuntimeReadiness,
        modelID: String,
        runtimeFingerprint: String
    ) {
        defaults.set(
            readiness.rawValue,
            forKey: key(modelID: modelID, runtimeFingerprint: runtimeFingerprint)
        )
    }

    private func key(modelID: String, runtimeFingerprint: String) -> String {
        "\(prefix).\(modelID).\(runtimeFingerprint)"
    }
}
