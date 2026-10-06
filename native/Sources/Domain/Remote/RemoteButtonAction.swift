import Foundation

enum RemoteButtonAction: String, CaseIterable, Codable {
    case pushToTalk
    case keyboardEscape
    case keyboardDelete
    case keyboardReturn
    case lockMac
    case send
    case cancel
    case toggleMainWindow
    case none
    case system

    static func allowedActions(for button: RemoteButton) -> [RemoteButtonAction] {
        RemoteActionCatalog.builtIn.allowedActions(for: button)
    }

    func isAllowed(for button: RemoteButton) -> Bool {
        Self.allowedActions(for: button).contains(self)
    }

    var replacesSystemEvent: Bool {
        RemoteActionCatalog.builtIn.descriptor(for: self)?.replacesSystemEvent ?? true
    }

    var startsRemoteSpeech: Bool {
        RemoteActionCatalog.builtIn.descriptor(for: self)?.startsRemoteSpeech ?? false
    }
}
