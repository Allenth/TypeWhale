import Foundation

enum RemoteActionFailureCode: String, Equatable {
    case unknownAction = "unknown_action"
    case invalidBinding = "invalid_binding"
    case executorFailed = "executor_failed"
    case powerNotNeutralized = "power_not_neutralized"
}

enum RemoteActionResult: Equatable {
    case passedThrough
    case suppressed
    case handedOff
    case succeeded
    case failed(RemoteActionFailureCode)

    var logCode: String {
        switch self {
        case .passedThrough:
            return "passed_through"
        case .suppressed:
            return "suppressed"
        case .handedOff:
            return "handed_off"
        case .succeeded:
            return "succeeded"
        case .failed(let code):
            return "failed_\(code.rawValue.replacingOccurrences(of: "_failed", with: ""))"
        }
    }
}

enum RemoteButtonActionDispatchResult: Equatable {
    case ignored
    case succeeded
    case failed
}

protocol RemoteKeyboardActionExecuting {
    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool
}

protocol RemoteSystemActionExecuting {
    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool
}

protocol RemoteTypeWhaleActionExecuting {
    func execute(_ descriptor: RemoteActionDescriptor, payload: RemoteActionPayload) -> Bool
}
