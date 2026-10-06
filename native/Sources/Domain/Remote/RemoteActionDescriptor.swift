import Foundation

enum RemoteActionFamily: String, Codable, Hashable {
    case remote
    case keyboard
    case typeWhale
    case system
}

struct RemoteActionDescriptor: Equatable {
    let id: RemoteActionID
    let revision: UInt16
    let legacyAction: RemoteButtonAction
    let family: RemoteActionFamily
    let supportedButtons: Set<RemoteButton>
    let replacesSystemEvent: Bool
    let startsRemoteSpeech: Bool

    func supports(_ button: RemoteButton) -> Bool {
        supportedButtons.contains(button)
    }
}
