import Foundation

struct RemoteButtonActionDispatcher {
    private let catalog: RemoteActionCatalog
    private let keyboardExecutor: any RemoteKeyboardActionExecuting
    private let systemExecutor: any RemoteSystemActionExecuting
    private let typeWhaleExecutor: any RemoteTypeWhaleActionExecuting

    init(
        catalog: RemoteActionCatalog = .builtIn,
        keyboardExecutor: any RemoteKeyboardActionExecuting,
        systemExecutor: any RemoteSystemActionExecuting,
        typeWhaleExecutor: any RemoteTypeWhaleActionExecuting
    ) {
        self.catalog = catalog
        self.keyboardExecutor = keyboardExecutor
        self.systemExecutor = systemExecutor
        self.typeWhaleExecutor = typeWhaleExecutor
    }

    init(
        showMainWindow: @escaping () -> Void,
        send: @escaping () -> Bool,
        cancelCurrentOperation: @escaping () -> Void,
        emitKeyboardAction: @escaping (RemoteButtonAction) -> Bool
    ) {
        self.init(
            keyboardExecutor: ClosureRemoteKeyboardActionExecutor(handler: emitKeyboardAction),
            systemExecutor: ClosureRemoteSystemActionExecutor(handler: emitKeyboardAction),
            typeWhaleExecutor: ClosureRemoteTypeWhaleActionExecutor(
                showMainWindow: showMainWindow,
                send: send,
                cancelCurrentOperation: cancelCurrentOperation
            )
        )
    }

    @discardableResult
    func dispatch(_ binding: RemoteBinding, for button: RemoteButton) -> RemoteActionResult {
        guard let descriptor = catalog.descriptor(for: binding.actionID) else {
            return .failed(.unknownAction)
        }
        guard catalog.resolve(binding, for: button) != nil else {
            return .failed(.invalidBinding)
        }

        if descriptor.id == .systemPassThrough {
            return .passedThrough
        }
        if descriptor.id == .none {
            return .suppressed
        }
        if descriptor.id == .pushToTalk {
            return .handedOff
        }

        let succeeded: Bool
        switch descriptor.family {
        case .keyboard:
            succeeded = keyboardExecutor.execute(descriptor, payload: binding.payload)
        case .system:
            succeeded = systemExecutor.execute(descriptor, payload: binding.payload)
        case .typeWhale:
            succeeded = typeWhaleExecutor.execute(descriptor, payload: binding.payload)
        case .remote:
            return .failed(.invalidBinding)
        }
        return succeeded ? .succeeded : .failed(.executorFailed)
    }

    @discardableResult
    func dispatch(_ action: RemoteButtonAction) -> RemoteButtonActionDispatchResult {
        let button: RemoteButton = action == .pushToTalk ? .voice : .home
        switch dispatch(catalog.binding(for: action), for: button) {
        case .passedThrough, .suppressed, .handedOff:
            return .ignored
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        }
    }
}
