import Foundation

struct ClosureRemoteKeyboardActionExecutor: RemoteKeyboardActionExecuting {
    let handler: (RemoteButtonAction) -> Bool

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        handler(descriptor.legacyAction)
    }
}

struct ClosureRemoteSystemActionExecutor: RemoteSystemActionExecuting {
    let handler: (RemoteButtonAction) -> Bool

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        handler(descriptor.legacyAction)
    }
}

struct ClosureRemoteTypeWhaleActionExecutor: RemoteTypeWhaleActionExecuting {
    let showMainWindow: () -> Void
    let send: () -> Bool
    let cancelCurrentOperation: () -> Void

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        switch descriptor.legacyAction {
        case .send:
            return send()
        case .cancel:
            cancelCurrentOperation()
            return true
        case .toggleMainWindow:
            showMainWindow()
            return true
        default:
            return false
        }
    }
}
