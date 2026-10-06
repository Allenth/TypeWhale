import Foundation

@main
struct ManagedLLMLifecyclePolicyCheck {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)

        precondition(
            action(
                selected: true,
                running: false,
                memory: 2_000,
                recoveryNotBefore: nil,
                now: now
            ) == .none
        )
        precondition(
            action(
                selected: true,
                running: false,
                memory: 2_000,
                coldPrewarmAllowed: true,
                recoveryNotBefore: nil,
                now: now
            ) == .prewarm
        )
        precondition(
            action(
                selected: true,
                running: true,
                memory: 4_100,
                recoveryNotBefore: nil,
                now: now
            ) == .stopForMemory
        )
        precondition(
            action(
                selected: true,
                running: false,
                memory: 4_100,
                recoveryNotBefore: nil,
                now: now
            ) == .none
        )
        precondition(
            action(
                selected: true,
                running: false,
                memory: 2_000,
                recoveryNotBefore: now.addingTimeInterval(1),
                now: now
            ) == .none
        )
        precondition(
            action(
                selected: true,
                running: false,
                memory: 2_000,
                projectedWorker: 3_000,
                recoveryNotBefore: now.addingTimeInterval(-1),
                now: now
            ) == .none
        )
        precondition(
            action(
                selected: true,
                running: false,
                memory: 500,
                projectedWorker: 3_000,
                recoveryNotBefore: now.addingTimeInterval(-1),
                now: now
            ) == .prewarm
        )
        precondition(
            action(
                selected: false,
                running: false,
                memory: 2_000,
                recoveryNotBefore: nil,
                now: now
            ) == .none
        )

        print("ManagedLLMLifecyclePolicyCheck passed")
    }

    private static func action(
        selected: Bool,
        running: Bool,
        memory: Int,
        projectedWorker: Int = 0,
        coldPrewarmAllowed: Bool = false,
        recoveryNotBefore: Date?,
        now: Date
    ) -> ManagedLLMLifecycleAction {
        ManagedLLMLifecyclePolicy.evaluate(
            .init(
                qwenSelected: selected,
                workerRunning: running,
                totalFootprintMB: memory,
                projectedWorkerFootprintMB: projectedWorker,
                warnThresholdMB: 4_000,
                coldPrewarmAllowed: coldPrewarmAllowed,
                recoveryNotBefore: recoveryNotBefore
            ),
            now: now
        )
    }
}
