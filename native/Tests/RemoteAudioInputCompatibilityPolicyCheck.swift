import Foundation

@main
struct RemoteAudioInputCompatibilityPolicyCheck {
    static func main() {
        precondition(RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: true,
            selectedDeviceName: "MiRemoteV 2ch"
        ))
        precondition(RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: true,
            selectedDeviceName: "MI REMOTE V"
        ))
        precondition(!RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: false,
            selectedDeviceName: "MiRemoteV 2ch"
        ))
        precondition(!RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: true,
            selectedDeviceName: "MacBook Pro麦克风"
        ))
        precondition(!RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: true,
            selectedDeviceName: "USB Audio Interface"
        ))
        precondition(!RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault(
            remoteFeatureEnabled: true,
            selectedDeviceName: nil
        ))
        print("RemoteAudioInputCompatibilityPolicyCheck passed")
    }
}
