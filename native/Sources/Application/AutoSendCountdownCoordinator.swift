import Foundation

@MainActor
protocol AutoSendCountdownPresenting: AnyObject {
    func show(
        snapshot: AutoSendCountdownSnapshot,
        onCancel: @escaping () -> Void
    )
    func update(snapshot: AutoSendCountdownSnapshot)
    func dismiss()
}

@MainActor
protocol AutoSendCountdownTimerToken: AnyObject {
    func invalidate()
}

@MainActor
protocol AutoSendCountdownTimerScheduling {
    func scheduleRepeating(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> any AutoSendCountdownTimerToken
}

@MainActor
final class AutoSendCountdownCoordinator: PostPasteActionScheduling {
    static let tickInterval: TimeInterval = 0.05

    private let presenter: any AutoSendCountdownPresenting
    private let timerScheduler: any AutoSendCountdownTimerScheduling
    private let durationSeconds: () -> Int
    private let now: () -> TimeInterval
    private let frontmostPID: () -> pid_t?
    private let emit: (PostPasteAction) -> Bool
    private let diagnostics: (String) -> Void
    private var pending: AutoSendCountdownRequest?
    private var timer: (any AutoSendCountdownTimerToken)?

    var onTerminal: ((AutoSendCountdownTerminalReason) -> Void)?

    var isCountingDown: Bool {
        pending != nil
    }

    init(
        presenter: any AutoSendCountdownPresenting,
        timerScheduler: any AutoSendCountdownTimerScheduling,
        durationSeconds: @escaping () -> Int,
        now: @escaping () -> TimeInterval,
        frontmostPID: @escaping () -> pid_t?,
        emit: @escaping (PostPasteAction) -> Bool,
        diagnostics: @escaping (String) -> Void
    ) {
        self.presenter = presenter
        self.timerScheduler = timerScheduler
        self.durationSeconds = durationSeconds
        self.now = now
        self.frontmostPID = frontmostPID
        self.emit = emit
        self.diagnostics = diagnostics
    }

    func schedule(
        action: PostPasteAction,
        taskID: UUID,
        targetPID: pid_t,
        targetBundleIdentifier: String?
    ) {
        guard PostPasteActionSchedulingGate.shouldSchedule(action) else {
            return
        }
        if let pending {
            finish(
                token: pending.token,
                reason: .cancelled(.replaced)
            )
        }

        let startedAt = now()
        let duration = TimeInterval(
            AutoSendConfiguration.normalizedCountdownSeconds(
                durationSeconds()
            )
        )
        let request = AutoSendCountdownRequest(
            token: UUID(),
            taskID: taskID,
            action: action,
            targetPID: targetPID,
            targetBundleIdentifier: targetBundleIdentifier,
            startedAt: startedAt,
            deadline: startedAt + duration
        )
        pending = request
        let snapshot = AutoSendCountdownSnapshot(
            token: request.token,
            action: action,
            remainingSeconds: duration
        )
        diagnostics(
            "auto_send_countdown_started token=\(short(request.token)) task_id=\(short(taskID)) action=\(action.rawValue) target_pid=\(targetPID) target_bundle=\(targetBundleIdentifier ?? "nil") duration_ms=\(Int(duration * 1000))"
        )
        presenter.show(snapshot: snapshot) { [weak self] in
            _ = self?.cancel(reason: .cancelButton)
        }
        let token = request.token
        timer = timerScheduler.scheduleRepeating(
            interval: Self.tickInterval
        ) { [weak self] in
            self?.tick(token: token)
        }
    }

    @discardableResult
    func cancel(reason: AutoSendCountdownCancelReason) -> Bool {
        guard let pending else { return false }
        finish(token: pending.token, reason: .cancelled(reason))
        return true
    }

    private func tick(token: UUID) {
        guard let request = pending, request.token == token else {
            return
        }
        switch AutoSendCountdownDecision.evaluate(
            request: request,
            now: now(),
            frontmostPID: frontmostPID()
        ) {
        case .continueCounting(let remainingSeconds):
            presenter.update(snapshot: AutoSendCountdownSnapshot(
                token: token,
                action: request.action,
                remainingSeconds: remainingSeconds
            ))
        case .emit:
            let emitted = emit(request.action)
            finish(
                token: token,
                reason: emitted
                    ? .emitted
                    : .skipped(.eventEmissionFailed)
            )
        case .skip(let reason):
            finish(token: token, reason: .skipped(reason))
        }
    }

    private func finish(
        token: UUID,
        reason: AutoSendCountdownTerminalReason
    ) {
        guard let request = pending, request.token == token else {
            return
        }
        timer?.invalidate()
        timer = nil
        pending = nil
        presenter.dismiss()
        diagnostics(
            "auto_send_countdown_terminal token=\(short(token)) task_id=\(short(request.taskID)) action=\(request.action.rawValue) target_pid=\(request.targetPID) reason=\(reason.logName)"
        )
        onTerminal?(reason)
    }

    private func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

@MainActor
final class MainRunLoopCountdownTimerScheduler:
    AutoSendCountdownTimerScheduling
{
    func scheduleRepeating(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> any AutoSendCountdownTimerToken {
        FoundationCountdownTimerToken(
            interval: interval,
            handler: handler
        )
    }
}

@MainActor
private final class FoundationCountdownTimerToken:
    NSObject,
    AutoSendCountdownTimerToken
{
    private var timer: Timer?
    private var handler: (() -> Void)?

    init(interval: TimeInterval, handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(fire),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func fire() {
        handler?()
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        handler = nil
    }

    deinit {
        timer?.invalidate()
    }
}

private extension AutoSendCountdownTerminalReason {
    var logName: String {
        switch self {
        case .emitted:
            return "emitted"
        case .cancelled(let reason):
            return "cancelled_\(reason.rawValue)"
        case .skipped(let reason):
            return "skipped_\(reason.rawValue)"
        }
    }
}
