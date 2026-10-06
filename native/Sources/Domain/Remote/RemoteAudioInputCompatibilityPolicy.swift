import Foundation

enum RemoteAudioInputCompatibilityPolicy {
    static func shouldMigrateToSystemDefault(
        remoteFeatureEnabled: Bool,
        selectedDeviceName: String?
    ) -> Bool {
        guard remoteFeatureEnabled, let selectedDeviceName else { return false }
        let normalized = selectedDeviceName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.hasPrefix("miremotev")
    }
}
