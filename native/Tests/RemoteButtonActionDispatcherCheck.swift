import Foundation

private final class KeyboardSpy: RemoteKeyboardActionExecuting {
    var actions: [RemoteButtonAction] = []
    var succeeds = true

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        actions.append(descriptor.legacyAction)
        return succeeds
    }
}

private final class SystemSpy: RemoteSystemActionExecuting {
    var actions: [RemoteButtonAction] = []

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        actions.append(descriptor.legacyAction)
        return true
    }
}

private final class TypeWhaleSpy: RemoteTypeWhaleActionExecuting {
    var actions: [RemoteButtonAction] = []

    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool {
        actions.append(descriptor.legacyAction)
        return true
    }
}

@main
struct RemoteButtonActionDispatcherCheck {
    static func main() {
        checkBindingRouting()
        checkCompatibilityInitializer()
        print("RemoteButtonActionDispatcherCheck passed")
    }

    private static func checkBindingRouting() {
        let keyboard = KeyboardSpy()
        let system = SystemSpy()
        let typeWhale = TypeWhaleSpy()
        let dispatcher = RemoteButtonActionDispatcher(
            catalog: .builtIn,
            keyboardExecutor: keyboard,
            systemExecutor: system,
            typeWhaleExecutor: typeWhale
        )
        let catalog = RemoteActionCatalog.builtIn

        precondition(dispatcher.dispatch(catalog.binding(for: .system), for: .back) == .passedThrough)
        precondition(dispatcher.dispatch(catalog.binding(for: .none), for: .menu) == .suppressed)
        precondition(dispatcher.dispatch(catalog.binding(for: .pushToTalk), for: .voice) == .handedOff)
        precondition(dispatcher.dispatch(catalog.binding(for: .keyboardEscape), for: .back) == .succeeded)
        precondition(dispatcher.dispatch(catalog.binding(for: .lockMac), for: .power) == .succeeded)
        precondition(dispatcher.dispatch(catalog.binding(for: .send), for: .home) == .succeeded)
        precondition(keyboard.actions == [.keyboardEscape])
        precondition(system.actions == [.lockMac])
        precondition(typeWhale.actions == [.send])

        keyboard.succeeds = false
        precondition(
            dispatcher.dispatch(catalog.binding(for: .keyboardDelete), for: .back) ==
                .failed(.executorFailed)
        )
        precondition(
            dispatcher.dispatch(
                RemoteBinding(actionID: RemoteActionID(rawValue: "future.action")),
                for: .home
            ) == .failed(.unknownAction)
        )
        precondition(
            dispatcher.dispatch(
                RemoteBinding(schemaVersion: 99, actionID: .typeWhaleSend),
                for: .home
            ) == .failed(.invalidBinding)
        )
        precondition(keyboard.actions == [.keyboardEscape, .keyboardDelete])
        precondition(system.actions == [.lockMac])
        precondition(typeWhale.actions == [.send])

        precondition(RemoteActionResult.passedThrough.logCode == "passed_through")
        precondition(RemoteActionResult.suppressed.logCode == "suppressed")
        precondition(RemoteActionResult.handedOff.logCode == "handed_off")
        precondition(RemoteActionResult.succeeded.logCode == "succeeded")
        precondition(RemoteActionResult.failed(.executorFailed).logCode == "failed_executor")
    }

    private static func checkCompatibilityInitializer() {
        var sendCount = 0
        var cancelCount = 0
        var showCount = 0
        var emittedKeyboardActions: [RemoteButtonAction] = []
        let dispatcher = RemoteButtonActionDispatcher(
            showMainWindow: { showCount += 1 },
            send: {
                sendCount += 1
                return true
            },
            cancelCurrentOperation: { cancelCount += 1 },
            emitKeyboardAction: {
                emittedKeyboardActions.append($0)
                return $0 != .keyboardDelete
            }
        )

        precondition(dispatcher.dispatch(.send) == .succeeded)
        precondition(dispatcher.dispatch(.cancel) == .succeeded)
        precondition(dispatcher.dispatch(.toggleMainWindow) == .succeeded)
        precondition(dispatcher.dispatch(.keyboardEscape) == .succeeded)
        precondition(dispatcher.dispatch(.keyboardDelete) == .failed)
        precondition(dispatcher.dispatch(.keyboardReturn) == .succeeded)
        precondition(dispatcher.dispatch(.lockMac) == .succeeded)
        precondition(dispatcher.dispatch(.system) == .ignored)
        precondition(dispatcher.dispatch(.none) == .ignored)
        precondition(dispatcher.dispatch(.pushToTalk) == .ignored)

        precondition(sendCount == 1)
        precondition(cancelCount == 1)
        precondition(showCount == 1)
        precondition(emittedKeyboardActions == [
            .keyboardEscape,
            .keyboardDelete,
            .keyboardReturn,
            .lockMac,
        ])
    }
}
