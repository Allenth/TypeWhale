import Foundation

struct AutoSendCountdownRequest: Equatable {
    let token: UUID
    let taskID: UUID
    let action: PostPasteAction
    let targetPID: pid_t
    let targetBundleIdentifier: String?
    let startedAt: TimeInterval
    let deadline: TimeInterval
}

struct AutoSendCountdownSnapshot: Equatable {
    let token: UUID
    let action: PostPasteAction
    let remainingSeconds: TimeInterval
}

@MainActor
protocol PostPasteActionScheduling: AnyObject {
    func schedule(
        action: PostPasteAction,
        taskID: UUID,
        targetPID: pid_t,
        targetBundleIdentifier: String?
    )
}

enum PostPasteActionSchedulingGate {
    static func shouldSchedule(_ action: PostPasteAction) -> Bool {
        action != .none
    }
}

enum AutoSendCountdownSkipReason: String, Equatable {
    case focusChanged
    case eventEmissionFailed
}

enum AutoSendCountdownCancelReason: String, Equatable {
    case cancelButton
    case escapeKey
    case rightMouseButton
    case manualSubmitKey
    case newRecording
    case replaced
    case appStopping
}

struct RightMouseCancellationGate {
    static let rightMouseButtonNumber = 1

    private var consumedMouseDown = false

    mutating func handle(
        buttonNumber: Int,
        isDown: Bool,
        cancel: () -> Bool
    ) -> Bool {
        guard buttonNumber == Self.rightMouseButtonNumber else { return false }
        if isDown {
            guard !consumedMouseDown else { return true }
            let cancelled = cancel()
            consumedMouseDown = cancelled
            return cancelled
        }
        guard consumedMouseDown else { return false }
        consumedMouseDown = false
        return true
    }

    mutating func reset() {
        consumedMouseDown = false
    }
}

enum AutoSendCountdownTerminalReason: Equatable {
    case emitted
    case cancelled(AutoSendCountdownCancelReason)
    case skipped(AutoSendCountdownSkipReason)
}

enum AutoSendCountdownDecision: Equatable {
    case continueCounting(remainingSeconds: TimeInterval)
    case emit
    case skip(AutoSendCountdownSkipReason)

    static func evaluate(
        request: AutoSendCountdownRequest,
        now: TimeInterval,
        frontmostPID: pid_t?
    ) -> Self {
        let remaining = max(0, request.deadline - now)
        if remaining > 0 {
            return .continueCounting(remainingSeconds: remaining)
        }
        guard frontmostPID == request.targetPID else {
            return .skip(.focusChanged)
        }
        return .emit
    }
}

enum AutoSendManualSubmitGate {
    static let syntheticEventUserData: Int64 = 0x5457_5053

    static func shouldCancelCountdown(
        keyCode: Int,
        isDown: Bool,
        eventUserData: Int64
    ) -> Bool {
        guard isDown, keyCode == 36 || keyCode == 76 else {
            return false
        }
        return eventUserData != syntheticEventUserData
    }
}
