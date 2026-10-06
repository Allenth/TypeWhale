import Foundation

@main
enum AutoSendCountdownDomainCheck {
    static func main() {
        let request = AutoSendCountdownRequest(
            token: UUID(),
            taskID: UUID(),
            action: .returnKey,
            targetPID: 42,
            targetBundleIdentifier: "com.example.chat",
            startedAt: 100,
            deadline: 101.5
        )
        guard case .continueCounting(let remaining) =
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 100.6,
                frontmostPID: 42
            ) else {
            preconditionFailure("countdown must still be active")
        }
        precondition(abs(remaining - 0.9) < 0.001)
        precondition(
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 101.5,
                frontmostPID: 42
            ) == .emit
        )
        precondition(
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 101.5,
                frontmostPID: 99
            ) == .skip(.focusChanged)
        )
        precondition(PostPasteActionSchedulingGate.shouldSchedule(.returnKey))
        precondition(PostPasteActionSchedulingGate.shouldSchedule(.commandReturn))
        precondition(!PostPasteActionSchedulingGate.shouldSchedule(.none))

        precondition(
            AutoSendManualSubmitGate.shouldCancelCountdown(
                keyCode: 36,
                isDown: true,
                eventUserData: 0
            )
        )
        precondition(
            AutoSendManualSubmitGate.shouldCancelCountdown(
                keyCode: 76,
                isDown: true,
                eventUserData: 0
            )
        )
        precondition(
            !AutoSendManualSubmitGate.shouldCancelCountdown(
                keyCode: 36,
                isDown: false,
                eventUserData: 0
            )
        )
        precondition(
            !AutoSendManualSubmitGate.shouldCancelCountdown(
                keyCode: 36,
                isDown: true,
                eventUserData: AutoSendManualSubmitGate.syntheticEventUserData
            )
        )
        precondition(
            !AutoSendManualSubmitGate.shouldCancelCountdown(
                keyCode: 12,
                isDown: true,
                eventUserData: 0
            )
        )
        print("AutoSendCountdownDomainCheck passed")
    }
}
