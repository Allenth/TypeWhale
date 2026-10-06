import Foundation

@main
enum RemoteActionCatalogCheck {
    static func main() throws {
        let catalog = RemoteActionCatalog.builtIn
        let expected: [(RemoteButtonAction, RemoteActionID)] = [
            (.pushToTalk, .pushToTalk),
            (.keyboardEscape, .keyboardEscape),
            (.keyboardDelete, .keyboardDeleteBackward),
            (.keyboardReturn, .keyboardReturn),
            (.lockMac, .lockMac),
            (.toggleMainWindow, .typeWhaleToggleMainWindow),
            (.send, .typeWhaleSend),
            (.cancel, .typeWhaleCancel),
            (.none, .none),
            (.system, .systemPassThrough),
        ]

        precondition(catalog.descriptors.count == 10)
        precondition(Set(catalog.descriptors.map(\.id)).count == 10)
        precondition(Set(catalog.descriptors.map(\.legacyAction)).count == 10)
        precondition(Set(RemoteButtonAction.allCases.map(\.rawValue)) == Set([
            "pushToTalk",
            "keyboardEscape",
            "keyboardDelete",
            "keyboardReturn",
            "lockMac",
            "send",
            "cancel",
            "toggleMainWindow",
            "none",
            "system",
        ]))

        for (action, id) in expected {
            let descriptor = catalog.descriptor(for: action)
            precondition(descriptor?.id == id)
            precondition(catalog.descriptor(for: id)?.legacyAction == action)
            let binding = catalog.binding(for: action)
            precondition(binding.actionID == id)
            precondition(binding.actionRevision == descriptor?.revision)
            precondition(binding.schemaVersion == RemoteBinding.currentSchemaVersion)
            precondition(binding.trigger == .primaryPress)
            precondition(binding.payload == .none)
        }

        let familyCounts = Dictionary(grouping: catalog.descriptors, by: \.family)
            .mapValues(\.count)
        precondition(familyCounts == [
            .remote: 3,
            .keyboard: 3,
            .typeWhale: 3,
            .system: 1,
        ])

        precondition(catalog.allowedActions(for: .voice) == [
            .pushToTalk,
            .system,
            .keyboardEscape,
            .keyboardDelete,
            .keyboardReturn,
            .lockMac,
            .toggleMainWindow,
            .send,
            .cancel,
            .none,
        ])
        precondition(catalog.allowedActions(for: .back) == [
            .system,
            .keyboardEscape,
            .keyboardDelete,
            .keyboardReturn,
            .lockMac,
            .toggleMainWindow,
            .send,
            .cancel,
            .none,
        ])

        precondition(catalog.resolve(catalog.binding(for: .pushToTalk), for: .voice) == .pushToTalk)
        precondition(catalog.resolve(catalog.binding(for: .pushToTalk), for: .back) == nil)
        precondition(catalog.resolve(
            RemoteBinding(actionID: RemoteActionID(rawValue: "future.action")),
            for: .home
        ) == nil)
        precondition(catalog.resolve(
            RemoteBinding(
                schemaVersion: RemoteBinding.currentSchemaVersion + 1,
                actionID: .typeWhaleSend
            ),
            for: .home
        ) == nil)
        precondition(catalog.resolve(
            RemoteBinding(actionID: .typeWhaleSend, actionRevision: 99),
            for: .home
        ) == nil)
        precondition(catalog.resolve(
            RemoteBinding(
                actionID: .typeWhaleSend,
                trigger: RemoteTrigger(schemaVersion: 99, id: .primaryPress)
            ),
            for: .home
        ) == nil)
        precondition(catalog.resolve(
            RemoteBinding(
                actionID: .typeWhaleSend,
                payload: RemoteActionPayload(schemaVersion: 99, kind: .none)
            ),
            for: .home
        ) == nil)

        let original = catalog.binding(for: .keyboardEscape)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteBinding.self, from: encoded)
        precondition(decoded == original)

        let encodedID = try JSONEncoder().encode(RemoteActionID.keyboardEscape)
        precondition(String(decoding: encodedID, as: UTF8.self) == #""keyboard.escape""#)
        let decodedID = try JSONDecoder().decode(RemoteActionID.self, from: encodedID)
        precondition(decodedID == .keyboardEscape)

        precondition(RemoteButtonAction.pushToTalk.startsRemoteSpeech)
        precondition(!RemoteButtonAction.system.replacesSystemEvent)
        for action in RemoteButtonAction.allCases where action != .system {
            precondition(action.replacesSystemEvent)
        }

        print("RemoteActionCatalogCheck passed")
    }
}
