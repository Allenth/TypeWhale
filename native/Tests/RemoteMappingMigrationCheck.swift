import Foundation

@main
enum RemoteMappingMigrationCheck {
    static func main() throws {
        let everyLegacyAction = Data(#"""
        {
          "actions": {
            "voice": "pushToTalk",
            "dpadUp": "keyboardEscape",
            "dpadDown": "keyboardDelete",
            "dpadLeft": "keyboardReturn",
            "dpadRight": "lockMac",
            "center": "send",
            "back": "cancel",
            "home": "toggleMainWindow",
            "menu": "none",
            "volumeUp": "system"
          }
        }
        """#.utf8)
        let legacy = try require(RemoteMappingMigration.decodeV1(everyLegacyAction))
        let migrated = RemoteMappingMigration.makeMapping(v2: nil, v1: legacy)
        precondition(migrated.action(for: .voice) == .pushToTalk)
        precondition(migrated.action(for: .dpadUp) == .keyboardEscape)
        precondition(migrated.action(for: .dpadDown) == .keyboardDelete)
        precondition(migrated.action(for: .dpadLeft) == .keyboardReturn)
        precondition(migrated.action(for: .dpadRight) == .lockMac)
        precondition(migrated.action(for: .center) == .send)
        precondition(migrated.action(for: .back) == .cancel)
        precondition(migrated.action(for: .home) == .toggleMainWindow)
        precondition(migrated.action(for: .menu) == .none)
        precondition(migrated.action(for: .volumeUp) == .system)

        let flattened = Data(#"{"actions":["home","send","back","keyboardEscape"]}"#.utf8)
        let flattenedMapping = RemoteMappingMigration.makeMapping(
            v2: nil,
            v1: try require(RemoteMappingMigration.decodeV1(flattened))
        )
        precondition(flattenedMapping.action(for: .home) == .send)
        precondition(flattenedMapping.action(for: .back) == .keyboardEscape)

        let damagedLegacyItem = Data(#"""
        {
          "actions": {
            "home": "send",
            "back": 7,
            "power": "lockMac",
            "voice": "pushToTalk"
          }
        }
        """#.utf8)
        let damagedLegacyMapping = RemoteMappingMigration.makeMapping(
            v2: nil,
            v1: try require(RemoteMappingMigration.decodeV1(damagedLegacyItem))
        )
        precondition(damagedLegacyMapping.action(for: .home) == .send)
        precondition(damagedLegacyMapping.action(for: .back) == .system)
        precondition(damagedLegacyMapping.action(for: .power) == .lockMac)
        precondition(damagedLegacyMapping.action(for: .voice) == .pushToTalk)

        let legacyFallback = try require(RemoteMappingMigration.decodeV1(
            Data(#"{"actions":{"home":"cancel","back":"keyboardEscape"}}"#.utf8)
        ))
        let partialV2 = Data(#"""
        {
          "schemaVersion": 2,
          "catalogRevision": 1,
          "bindings": {
            "home": {
              "schemaVersion": 2,
              "actionID": "typewhale.send",
              "actionRevision": 1,
              "trigger": {"schemaVersion": 1, "id": "remote.primaryPress"},
              "payload": {"schemaVersion": 1, "kind": "none"}
            },
            "back": {
              "schemaVersion": 2,
              "actionID": "future.action",
              "actionRevision": 1,
              "trigger": {"schemaVersion": 1, "id": "remote.primaryPress"},
              "payload": {"schemaVersion": 1, "kind": "none"}
            },
            "power": 17
          }
        }
        """#.utf8)
        let v2 = try require(RemoteMappingMigration.decodeV2(partialV2))
        let layered = RemoteMappingMigration.makeMapping(v2: v2, v1: legacyFallback)
        precondition(layered.action(for: .home) == .send)
        precondition(layered.action(for: .back) == .keyboardEscape)
        precondition(layered.action(for: .power) == .system)
        precondition(layered.action(for: .voice) == .pushToTalk)

        var roundTripSource = RemoteButtonMapping.defaults
        roundTripSource.set(.send, for: .home)
        roundTripSource.set(.keyboardEscape, for: .back)
        let v2Data = try require(RemoteMappingMigration.encodeV2(roundTripSource))
        let decodedV2 = try require(RemoteMappingMigration.decodeV2(v2Data))
        precondition(RemoteMappingMigration.makeMapping(v2: decodedV2, v1: nil) == roundTripSource)

        let v1Data = try require(RemoteMappingMigration.encodeV1(roundTripSource))
        let v1Object = try JSONSerialization.jsonObject(with: v1Data) as? [String: Any]
        let v1Actions = v1Object?["actions"] as? [String: String]
        precondition(v1Actions?["home"] == "send")
        precondition(v1Actions?["back"] == "keyboardEscape")
        precondition(v1Object?["bindings"] == nil)

        precondition(RemoteMappingMigration.decodeV1(Data("not-json".utf8)) == nil)
        precondition(RemoteMappingMigration.decodeV2(Data("not-json".utf8)) == nil)
        precondition(RemoteMappingMigration.decodeV2(
            Data(#"{"schemaVersion":99,"catalogRevision":1,"bindings":{}}"#.utf8)
        ) == nil)

        print("RemoteMappingMigrationCheck passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw NSError(domain: "RemoteMappingMigrationCheck", code: 1)
        }
        return value
    }
}
