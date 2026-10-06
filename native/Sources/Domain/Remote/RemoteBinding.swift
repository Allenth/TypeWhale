import Foundation

struct RemoteActionPayload: Codable, Equatable {
    enum Kind: String, Codable {
        case none
    }

    static let currentSchemaVersion: UInt16 = 1

    let schemaVersion: UInt16
    let kind: Kind

    init(
        schemaVersion: UInt16 = currentSchemaVersion,
        kind: Kind
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
    }

    static let none = RemoteActionPayload(kind: .none)

    var isSupported: Bool {
        schemaVersion == Self.currentSchemaVersion && kind == .none
    }
}

struct RemoteBinding: Codable, Equatable {
    static let currentSchemaVersion: UInt16 = 2

    let schemaVersion: UInt16
    let actionID: RemoteActionID
    let actionRevision: UInt16
    let trigger: RemoteTrigger
    let payload: RemoteActionPayload

    init(
        schemaVersion: UInt16 = currentSchemaVersion,
        actionID: RemoteActionID,
        actionRevision: UInt16 = 1,
        trigger: RemoteTrigger = .primaryPress,
        payload: RemoteActionPayload = .none
    ) {
        self.schemaVersion = schemaVersion
        self.actionID = actionID
        self.actionRevision = actionRevision
        self.trigger = trigger
        self.payload = payload
    }

    var descriptor: RemoteActionDescriptor? {
        guard schemaVersion == Self.currentSchemaVersion,
              trigger.isSupported,
              payload.isSupported,
              let descriptor = RemoteActionCatalog.builtIn.descriptor(for: actionID),
              actionRevision == descriptor.revision else { return nil }
        return descriptor
    }

    var replacesSystemEvent: Bool {
        descriptor?.replacesSystemEvent ?? true
    }

    var startsRemoteSpeech: Bool {
        descriptor?.startsRemoteSpeech ?? false
    }
}
