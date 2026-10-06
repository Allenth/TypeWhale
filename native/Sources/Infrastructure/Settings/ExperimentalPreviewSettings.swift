import Foundation

struct ExperimentalPreviewSettings: Equatable, Sendable {
    var correctedPreviewEnabled: Bool
    var longFormIncrementalOutputEnabled: Bool

    func normalized(supportsSenseVoice: Bool) -> ExperimentalPreviewSettings {
        guard supportsSenseVoice else {
            return ExperimentalPreviewSettings(
                correctedPreviewEnabled: false,
                longFormIncrementalOutputEnabled: false
            )
        }
        return ExperimentalPreviewSettings(
            correctedPreviewEnabled: correctedPreviewEnabled || longFormIncrementalOutputEnabled,
            longFormIncrementalOutputEnabled: longFormIncrementalOutputEnabled
        )
    }
}

struct ExperimentalPreviewSettingsStore {
    private enum Key {
        static let correctedPreview = "experimentalCorrectedPreview"
        static let longFormIncrementalOutput = "experimentalLongFormIncrementalOutput"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExperimentalPreviewSettings {
        ExperimentalPreviewSettings(
            correctedPreviewEnabled: defaults.bool(forKey: Key.correctedPreview),
            longFormIncrementalOutputEnabled: defaults.bool(forKey: Key.longFormIncrementalOutput)
        )
    }

    func save(_ settings: ExperimentalPreviewSettings) {
        defaults.set(settings.correctedPreviewEnabled, forKey: Key.correctedPreview)
        defaults.set(settings.longFormIncrementalOutputEnabled, forKey: Key.longFormIncrementalOutput)
    }
}
