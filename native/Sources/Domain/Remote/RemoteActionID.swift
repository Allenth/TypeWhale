import Foundation

struct RemoteActionID: RawRepresentable, Codable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let pushToTalk = RemoteActionID(rawValue: "remote.pushToTalk")
    static let systemPassThrough = RemoteActionID(rawValue: "remote.systemPassThrough")
    static let none = RemoteActionID(rawValue: "remote.none")
    static let keyboardEscape = RemoteActionID(rawValue: "keyboard.escape")
    static let keyboardDeleteBackward = RemoteActionID(rawValue: "keyboard.deleteBackward")
    static let keyboardReturn = RemoteActionID(rawValue: "keyboard.return")
    static let lockMac = RemoteActionID(rawValue: "system.lockMac")
    static let typeWhaleToggleMainWindow = RemoteActionID(rawValue: "typewhale.toggleMainWindow")
    static let typeWhaleSend = RemoteActionID(rawValue: "typewhale.send")
    static let typeWhaleCancel = RemoteActionID(rawValue: "typewhale.cancel")
}
