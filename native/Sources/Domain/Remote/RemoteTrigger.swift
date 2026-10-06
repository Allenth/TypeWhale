import Foundation

struct RemoteTriggerID: RawRepresentable, Codable, Hashable {
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

    static let primaryPress = RemoteTriggerID(rawValue: "remote.primaryPress")
}

struct RemoteTrigger: Codable, Equatable {
    static let currentSchemaVersion: UInt16 = 1

    let schemaVersion: UInt16
    let id: RemoteTriggerID

    init(
        schemaVersion: UInt16 = currentSchemaVersion,
        id: RemoteTriggerID
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
    }

    static let primaryPress = RemoteTrigger(id: .primaryPress)

    var isSupported: Bool {
        schemaVersion == Self.currentSchemaVersion && id == .primaryPress
    }
}
