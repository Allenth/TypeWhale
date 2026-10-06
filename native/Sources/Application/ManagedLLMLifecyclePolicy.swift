import Foundation

enum ManagedLLMLifecycleAction: Equatable {
    case none
    case prewarm
    case stopForMemory
}

enum ManagedLLMLifecyclePolicy {
    struct Input: Equatable {
        let qwenSelected: Bool
        let workerRunning: Bool
        let totalFootprintMB: Int
        let projectedWorkerFootprintMB: Int
        let warnThresholdMB: Int
        let coldPrewarmAllowed: Bool
        let recoveryNotBefore: Date?
    }

    static let recoveryCooldown: TimeInterval = 30

    static func evaluate(
        _ input: Input,
        now: Date
    ) -> ManagedLLMLifecycleAction {
        guard input.qwenSelected else { return .none }

        if input.totalFootprintMB >= input.warnThresholdMB {
            return input.workerRunning ? .stopForMemory : .none
        }
        guard !input.workerRunning else { return .none }

        if let recoveryNotBefore = input.recoveryNotBefore {
            guard now >= recoveryNotBefore else { return .none }
            let recoveryThresholdMB = input.warnThresholdMB * 3 / 4
            guard input.totalFootprintMB <= recoveryThresholdMB else {
                return .none
            }
            guard input.totalFootprintMB
                    + input.projectedWorkerFootprintMB
                    < input.warnThresholdMB else {
                return .none
            }
        } else {
            guard input.coldPrewarmAllowed else { return .none }
        }
        return .prewarm
    }
}
