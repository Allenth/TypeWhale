import Foundation

struct MainCapsuleOpenClawProjection: Equatable {
    let purpose: MainCapsulePurposeAppearance

    init(accent: PreviewAccent, connectionStatus: OpenClawConnectionStatus) {
        switch accent {
        case .normal:
            self.purpose = .dictation
        case .ideaPill:
            self.purpose = .ideaPill
        case .openClaw:
            self.purpose = .openClaw(
                connection: MainCapsuleOpenClawConnectionStatus(legacy: connectionStatus)
            )
        }
    }
}

extension MainCapsuleOpenClawConnectionStatus {
    init(legacy status: OpenClawConnectionStatus) {
        switch status {
        case .checking:
            self = .checking
        case .connected:
            self = .connected
        case .unavailable:
            self = .unavailable
        }
    }
}
