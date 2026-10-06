import Foundation

@main
struct RemoteButtonMappingCheck {
    static func main() throws {
        let defaults = RemoteButtonMapping.defaults
        let expectedDefaults: [RemoteButton: RemoteButtonAction] = [
            .voice: .pushToTalk,
            .dpadUp: .system,
            .dpadDown: .system,
            .dpadLeft: .system,
            .dpadRight: .system,
            .center: .system,
            .back: .system,
            .home: .toggleMainWindow,
            .menu: .none,
            .volumeUp: .system,
            .volumeDown: .system,
            .tv: .system,
            .power: .system,
        ]
        precondition(expectedDefaults.count == RemoteButton.allCases.count)
        for button in RemoteButton.allCases {
            precondition(defaults.action(for: button) == expectedDefaults[button])
            precondition(
                RemoteActionCatalog.builtIn.resolve(defaults.binding(for: button), for: button) ==
                    expectedDefaults[button]
            )
            precondition(defaults.canEdit(button))
            let allowed = RemoteButtonAction.allowedActions(for: button)
            precondition(allowed.contains(.system))
            precondition(allowed.contains(.none))
            precondition(allowed.contains(.keyboardDelete))
            precondition(allowed.contains(.pushToTalk) == (button == .voice))
        }
        precondition(RemoteButtonAction.allowedActions(for: .back).contains(.keyboardEscape))
        precondition(RemoteButtonAction.allowedActions(for: .power).contains(.lockMac))

        var edited = defaults
        for button in RemoteButton.allCases {
            edited.set(.send, for: button)
            precondition(edited.action(for: button) == .send)
        }
        edited.set(.pushToTalk, for: .back)
        precondition(edited.action(for: .back) == .system)
        edited.set(.keyboardEscape, for: .back)
        precondition(edited.action(for: .back) == .keyboardEscape)
        edited.set(.lockMac, for: .power)
        precondition(edited.action(for: .power) == .lockMac)
        precondition(edited.binding(for: .power).actionID == .lockMac)

        edited.set(RemoteBinding(actionID: .typeWhaleCancel), for: .tv)
        precondition(edited.action(for: .tv) == .cancel)
        edited.set(RemoteBinding(actionID: .pushToTalk), for: .back)
        precondition(edited.action(for: .back) == .system)

        let data = try require(RemoteMappingMigration.encodeV2(edited))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        precondition(object?["schemaVersion"] as? Int == 2)
        precondition(object?["catalogRevision"] as? Int == 1)
        precondition(object?["bindings"] as? [String: Any] != nil)
        precondition(object?["actions"] == nil)
        let decoded = RemoteMappingMigration.makeMapping(
            v2: try require(RemoteMappingMigration.decodeV2(data)),
            v1: nil
        )
        precondition(decoded == edited)
        print("RemoteButtonMappingCheck passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw NSError(domain: "RemoteButtonMappingCheck", code: 1)
        }
        return value
    }
}
