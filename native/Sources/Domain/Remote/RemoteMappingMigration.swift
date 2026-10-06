import Foundation

struct RemoteMappingV1Snapshot: Equatable {
    fileprivate let actions: [RemoteButton: RemoteButtonAction]
}

struct RemoteMappingV2Snapshot: Equatable {
    fileprivate let bindings: [RemoteButton: RemoteBinding]
    fileprivate let opaqueBindings: [String: Data]
}

enum RemoteMappingMigration {
    static let mappingSchemaVersion: UInt16 = 2

    static func decodeV1(_ data: Data) -> RemoteMappingV1Snapshot? {
        guard let document = try? JSONDecoder().decode(RemoteMappingV1Document.self, from: data)
        else { return nil }

        var actions: [RemoteButton: RemoteButtonAction] = [:]
        for (buttonID, actionID) in document.actions {
            guard let button = RemoteButton(rawValue: buttonID),
                  let action = RemoteButtonAction(rawValue: actionID),
                  action.isAllowed(for: button) else { continue }
            actions[button] = action
        }
        return RemoteMappingV1Snapshot(actions: actions)
    }

    static func decodeV2(_ data: Data) -> RemoteMappingV2Snapshot? {
        guard let document = try? JSONDecoder().decode(RemoteMappingV2Document.self, from: data)
        else { return nil }
        let current = snapshot(from: document)
        return RemoteMappingV2Snapshot(
            bindings: current.bindings,
            opaqueBindings: opaqueBindings(in: data, excluding: current.bindings)
        )
    }

    private static func snapshot(
        from document: RemoteMappingV2Document
    ) -> RemoteMappingV2Snapshot {
        var bindings: [RemoteButton: RemoteBinding] = [:]
        for (buttonID, binding) in document.bindings {
            guard let button = RemoteButton(rawValue: buttonID),
                  RemoteActionCatalog.builtIn.resolve(binding, for: button) != nil else { continue }
            bindings[button] = binding
        }
        return RemoteMappingV2Snapshot(bindings: bindings, opaqueBindings: [:])
    }

    static func encodeV1(_ mapping: RemoteButtonMapping) -> Data? {
        let actions = Dictionary(uniqueKeysWithValues: RemoteButton.allCases.map { button in
            (button.rawValue, mapping.action(for: button).rawValue)
        })
        return try? JSONEncoder().encode(RemoteMappingV1EncodingDocument(actions: actions))
    }

    static func encodeV2(_ mapping: RemoteButtonMapping) -> Data? {
        let bindings = Dictionary(uniqueKeysWithValues: mapping.storedBindings.map { button, binding in
            (button.rawValue, binding)
        })
        guard let knownData = try? JSONEncoder().encode(
            RemoteMappingV2EncodingDocument(
                schemaVersion: mappingSchemaVersion,
                catalogRevision: RemoteActionCatalog.currentRevision,
                bindings: bindings
            )
        ),
        var root = try? JSONSerialization.jsonObject(with: knownData) as? [String: Any],
        var encodedBindings = root["bindings"] as? [String: Any] else { return nil }

        for (buttonID, data) in mapping.storedOpaqueBindings {
            guard let value = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ) else { continue }
            encodedBindings[buttonID] = value
        }
        root["bindings"] = encodedBindings
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    static func makeMapping(
        v2: RemoteMappingV2Snapshot?,
        v1: RemoteMappingV1Snapshot?
    ) -> RemoteButtonMapping {
        var recovered: [RemoteButton: RemoteBinding] = [:]
        for button in RemoteButton.allCases {
            if let binding = v2?.bindings[button] {
                recovered[button] = binding
            } else if let action = v1?.actions[button] {
                recovered[button] = RemoteActionCatalog.builtIn.binding(for: action)
            }
        }
        return RemoteButtonMapping.recovering(
            recovered,
            opaqueBindings: v2?.opaqueBindings ?? [:]
        )
    }

    private static func opaqueBindings(
        in data: Data,
        excluding validBindings: [RemoteButton: RemoteBinding]
    ) -> [String: Data] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawBindings = root["bindings"] as? [String: Any] else { return [:] }

        var opaque: [String: Data] = [:]
        for (buttonID, value) in rawBindings {
            if let button = RemoteButton(rawValue: buttonID), validBindings[button] != nil {
                continue
            }
            guard let rawData = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .sortedKeys]
            ) else { continue }
            opaque[buttonID] = rawData
        }
        return opaque
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct RemoteMappingV1Document: Decodable {
    let actions: [String: String]

    private enum CodingKeys: String, CodingKey {
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dictionary = try? container.decode(
            [String: LossyDecodable<String>].self,
            forKey: .actions
        ) {
            actions = dictionary.compactMapValues(\.value)
            return
        }
        if let flattened = try? container.decode([String].self, forKey: .actions) {
            var recovered: [String: String] = [:]
            var index = 0
            while index + 1 < flattened.count {
                recovered[flattened[index]] = flattened[index + 1]
                index += 2
            }
            actions = recovered
            return
        }
        actions = [:]
    }
}

private struct RemoteMappingV1EncodingDocument: Encodable {
    let actions: [String: String]
}

private struct RemoteMappingV2Document: Decodable {
    let bindings: [String: RemoteBinding]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case catalogRevision
        case bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
        guard schemaVersion == RemoteMappingMigration.mappingSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported remote mapping schema \(schemaVersion)"
            )
        }
        _ = try container.decode(UInt16.self, forKey: .catalogRevision)
        let lossyBindings = try container.decode(
            [String: LossyDecodable<RemoteBinding>].self,
            forKey: .bindings
        )
        bindings = lossyBindings.compactMapValues(\.value)
    }
}

private struct RemoteMappingV2EncodingDocument: Encodable {
    let schemaVersion: UInt16
    let catalogRevision: UInt16
    let bindings: [String: RemoteBinding]
}
