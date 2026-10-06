import Foundation

@main
struct RemoteInputSettingsStoreCheck {
    static func main() throws {
        let suiteName = "TypeWhale.RemoteInputSettingsStoreCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RemoteInputSettingsStore(defaults: defaults)

        precondition(store.loadEnabled())
        store.saveEnabled(false)
        precondition(!store.loadEnabled())
        precondition(store.loadMappings() == .defaults)
        precondition(defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key) == nil)

        var edited = RemoteButtonMapping.defaults
        edited.set(.send, for: .home)
        edited.set(.keyboardEscape, for: .back)
        store.saveMappings(edited)
        precondition(store.loadMappings() == edited)
        let savedV2 = defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key)
        let savedV1 = defaults.data(forKey: RemoteInputSettingsStore.mappingKey)
        precondition(savedV2 != nil)
        precondition(savedV1 != nil)
        let legacyRoundTrip = RemoteMappingMigration.makeMapping(
            v2: nil,
            v1: try require(RemoteMappingMigration.decodeV1(try require(savedV1)))
        )
        precondition(legacyRoundTrip == edited)

        let legacyOnly = Data(#"{"actions":{"home":"cancel","back":"keyboardEscape"}}"#.utf8)
        defaults.removeObject(forKey: RemoteInputSettingsStore.mappingV2Key)
        defaults.set(legacyOnly, forKey: RemoteInputSettingsStore.mappingKey)
        let migrated = store.loadMappings()
        precondition(migrated.action(for: .home) == .cancel)
        precondition(migrated.action(for: .back) == .keyboardEscape)
        precondition(migrated.action(for: .center) == .system)
        precondition(migrated.action(for: .voice) == .pushToTalk)
        precondition(defaults.data(forKey: RemoteInputSettingsStore.mappingKey) == legacyOnly)
        precondition(defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key) != nil)

        let conflictingV1 = Data(#"{"actions":{"home":"cancel","back":"keyboardEscape"}}"#.utf8)
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
            "futureButton": {
              "schemaVersion": 3,
              "actionID": "future.buttonAction",
              "actionRevision": 4,
              "trigger": {"schemaVersion": 2, "id": "future.doublePress"},
              "payload": {"schemaVersion": 2, "kind": "futurePayload", "value": 17}
            },
            "power": {"schemaVersion": 2, "actionID": 9}
          }
        }
        """#.utf8)
        defaults.set(conflictingV1, forKey: RemoteInputSettingsStore.mappingKey)
        defaults.set(partialV2, forKey: RemoteInputSettingsStore.mappingV2Key)
        let layered = store.loadMappings()
        precondition(layered.action(for: .home) == .send)
        precondition(layered.action(for: .back) == .keyboardEscape)
        precondition(layered.action(for: .power) == .system)
        precondition(defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key) == partialV2)

        var editedLayered = layered
        editedLayered.set(.cancel, for: .home)
        store.saveMappings(editedLayered)
        let forwardCompatibleData = try require(
            defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key)
        )
        let forwardCompatibleRoot = try require(
            JSONSerialization.jsonObject(with: forwardCompatibleData) as? [String: Any]
        )
        let forwardCompatibleBindings = try require(
            forwardCompatibleRoot["bindings"] as? [String: Any]
        )
        let preservedFutureBack = try require(
            forwardCompatibleBindings["back"] as? [String: Any]
        )
        precondition(preservedFutureBack["actionID"] as? String == "future.action")
        let preservedDamagedPower = try require(
            forwardCompatibleBindings["power"] as? [String: Any]
        )
        precondition((preservedDamagedPower["actionID"] as? NSNumber)?.intValue == 9)
        let preservedFutureButton = try require(
            forwardCompatibleBindings["futureButton"] as? [String: Any]
        )
        precondition(preservedFutureButton["actionID"] as? String == "future.buttonAction")
        let editedHome = try require(
            forwardCompatibleBindings["home"] as? [String: Any]
        )
        precondition(editedHome["actionID"] as? String == "typewhale.cancel")

        var explicitlyEdited = store.loadMappings()
        explicitlyEdited.set(.keyboardEscape, for: .back)
        store.saveMappings(explicitlyEdited)
        let explicitlyEditedData = try require(
            defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key)
        )
        let explicitlyEditedRoot = try require(
            JSONSerialization.jsonObject(with: explicitlyEditedData) as? [String: Any]
        )
        let explicitlyEditedBindings = try require(
            explicitlyEditedRoot["bindings"] as? [String: Any]
        )
        let explicitlyEditedBack = try require(
            explicitlyEditedBindings["back"] as? [String: Any]
        )
        precondition(explicitlyEditedBack["actionID"] as? String == "keyboard.escape")
        precondition(explicitlyEditedBindings["futureButton"] != nil)

        let damagedV2 = Data("not-json".utf8)
        defaults.set(damagedV2, forKey: RemoteInputSettingsStore.mappingV2Key)
        defaults.set(conflictingV1, forKey: RemoteInputSettingsStore.mappingKey)
        let v1Fallback = store.loadMappings()
        precondition(v1Fallback.action(for: .home) == .cancel)
        precondition(v1Fallback.action(for: .back) == .keyboardEscape)
        precondition(defaults.data(forKey: RemoteInputSettingsStore.mappingV2Key) == damagedV2)

        let damagedLegacyItem = Data(
            #"{"actions":{"home":"send","back":7,"power":"lockMac"}}"#.utf8
        )
        defaults.removeObject(forKey: RemoteInputSettingsStore.mappingV2Key)
        defaults.set(damagedLegacyItem, forKey: RemoteInputSettingsStore.mappingKey)
        let recoveredLegacy = store.loadMappings()
        precondition(recoveredLegacy.action(for: .home) == .send)
        precondition(recoveredLegacy.action(for: .back) == .system)
        precondition(recoveredLegacy.action(for: .power) == .lockMac)

        defaults.set(Data("not-json".utf8), forKey: RemoteInputSettingsStore.mappingV2Key)
        defaults.set(Data("not-json".utf8), forKey: RemoteInputSettingsStore.mappingKey)
        precondition(store.loadMappings() == .defaults)
        print("RemoteInputSettingsStoreCheck passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw NSError(domain: "RemoteInputSettingsStoreCheck", code: 1)
        }
        return value
    }
}
