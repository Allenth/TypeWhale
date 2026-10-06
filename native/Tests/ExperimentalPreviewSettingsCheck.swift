import Foundation

@main
struct ExperimentalPreviewSettingsCheck {
    static func main() {
        let defaults = ExperimentalPreviewSettings(correctedPreviewEnabled: false, longFormIncrementalOutputEnabled: false)
        precondition(defaults.normalized(supportsSenseVoice: true) == defaults)

        let longOnly = ExperimentalPreviewSettings(correctedPreviewEnabled: false, longFormIncrementalOutputEnabled: true)
        let normalizedLong = longOnly.normalized(supportsSenseVoice: true)
        precondition(normalizedLong.correctedPreviewEnabled)
        precondition(normalizedLong.longFormIncrementalOutputEnabled)

        // 桌面胶囊是否可见不属于矫正设置的归一化输入；关闭胶囊不能改写矫正偏好。
        let capsuleHidden = normalizedLong.normalized(supportsSenseVoice: true)
        precondition(capsuleHidden.correctedPreviewEnabled)
        precondition(capsuleHidden.longFormIncrementalOutputEnabled)

        let unsupported = normalizedLong.normalized(supportsSenseVoice: false)
        precondition(!unsupported.correctedPreviewEnabled)
        precondition(!unsupported.longFormIncrementalOutputEnabled)

        let suiteName = "ExperimentalPreviewSettingsCheck.\(UUID().uuidString)"
        let storeDefaults = UserDefaults(suiteName: suiteName)!
        defer { storeDefaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalPreviewSettingsStore(defaults: storeDefaults)
        precondition(store.load() == defaults)
        store.save(normalizedLong)
        precondition(store.load() == normalizedLong)

        print("ExperimentalPreviewSettingsCheck passed")
    }
}
