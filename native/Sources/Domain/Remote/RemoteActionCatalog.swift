import Foundation

struct RemoteActionCatalog {
    static let currentRevision: UInt16 = 1

    let descriptors: [RemoteActionDescriptor]

    static let builtIn = RemoteActionCatalog(descriptors: makeBuiltInDescriptors())

    func descriptor(for id: RemoteActionID) -> RemoteActionDescriptor? {
        descriptors.first { $0.id == id }
    }

    func descriptor(for action: RemoteButtonAction) -> RemoteActionDescriptor? {
        descriptors.first { $0.legacyAction == action }
    }

    func binding(for action: RemoteButtonAction) -> RemoteBinding {
        guard let descriptor = descriptor(for: action) else {
            preconditionFailure("Remote action catalog is missing \(action.rawValue)")
        }
        return RemoteBinding(
            actionID: descriptor.id,
            actionRevision: descriptor.revision
        )
    }

    func resolve(_ binding: RemoteBinding, for button: RemoteButton) -> RemoteButtonAction? {
        guard binding.schemaVersion == RemoteBinding.currentSchemaVersion,
              binding.trigger.isSupported,
              binding.payload.isSupported,
              let descriptor = descriptor(for: binding.actionID),
              binding.actionRevision == descriptor.revision,
              descriptor.supports(button) else { return nil }
        return descriptor.legacyAction
    }

    func allowedActions(for button: RemoteButton) -> [RemoteButtonAction] {
        descriptors.compactMap { descriptor in
            descriptor.supports(button) ? descriptor.legacyAction : nil
        }
    }

    private static func makeBuiltInDescriptors() -> [RemoteActionDescriptor] {
        let allButtons = Set(RemoteButton.allCases)
        let voiceOnly: Set<RemoteButton> = [.voice]
        return [
            RemoteActionDescriptor(
                id: .pushToTalk,
                revision: 1,
                legacyAction: .pushToTalk,
                family: .remote,
                supportedButtons: voiceOnly,
                replacesSystemEvent: true,
                startsRemoteSpeech: true
            ),
            RemoteActionDescriptor(
                id: .systemPassThrough,
                revision: 1,
                legacyAction: .system,
                family: .remote,
                supportedButtons: allButtons,
                replacesSystemEvent: false,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .keyboardEscape,
                revision: 1,
                legacyAction: .keyboardEscape,
                family: .keyboard,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .keyboardDeleteBackward,
                revision: 1,
                legacyAction: .keyboardDelete,
                family: .keyboard,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .keyboardReturn,
                revision: 1,
                legacyAction: .keyboardReturn,
                family: .keyboard,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .lockMac,
                revision: 1,
                legacyAction: .lockMac,
                family: .system,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .typeWhaleToggleMainWindow,
                revision: 1,
                legacyAction: .toggleMainWindow,
                family: .typeWhale,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .typeWhaleSend,
                revision: 1,
                legacyAction: .send,
                family: .typeWhale,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .typeWhaleCancel,
                revision: 1,
                legacyAction: .cancel,
                family: .typeWhale,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
            RemoteActionDescriptor(
                id: .none,
                revision: 1,
                legacyAction: .none,
                family: .remote,
                supportedButtons: allButtons,
                replacesSystemEvent: true,
                startsRemoteSpeech: false
            ),
        ]
    }
}
