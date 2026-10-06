import Foundation

@MainActor
private final class FakeCountdownPresenter: AutoSendCountdownPresenting {
    var shown: [AutoSendCountdownSnapshot] = []
    var updated: [AutoSendCountdownSnapshot] = []
    var dismissCount = 0
    private var onCancel: (() -> Void)?

    func show(
        snapshot: AutoSendCountdownSnapshot,
        onCancel: @escaping () -> Void
    ) {
        shown.append(snapshot)
        self.onCancel = onCancel
    }

    func update(snapshot: AutoSendCountdownSnapshot) {
        updated.append(snapshot)
    }

    func dismiss() {
        dismissCount += 1
        onCancel = nil
    }

    func clickCancel() {
        onCancel?()
    }
}

@MainActor
private final class FakeCountdownTimerToken: AutoSendCountdownTimerToken {
    var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func invalidate() {
        handler = nil
    }
}

@MainActor
private final class FakeCountdownTimerScheduler:
    AutoSendCountdownTimerScheduling
{
    private(set) var tokens: [FakeCountdownTimerToken] = []

    func scheduleRepeating(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> any AutoSendCountdownTimerToken {
        precondition(abs(interval - 0.05) < 0.001)
        let token = FakeCountdownTimerToken(handler: handler)
        tokens.append(token)
        return token
    }

    func fireAll() {
        tokens.compactMap(\.handler).forEach { $0() }
    }
}

@MainActor
@main
enum AutoSendCountdownCoordinatorCheck {
    static func main() {
        var now: TimeInterval = 100
        var frontmostPID: pid_t? = 42
        var emitted: [PostPasteAction] = []
        var terminals: [AutoSendCountdownTerminalReason] = []
        var diagnostics: [String] = []
        var emitSucceeds = true
        var durationSeconds = 1
        let presenter = FakeCountdownPresenter()
        let scheduler = FakeCountdownTimerScheduler()
        let coordinator = AutoSendCountdownCoordinator(
            presenter: presenter,
            timerScheduler: scheduler,
            durationSeconds: { durationSeconds },
            now: { now },
            frontmostPID: { frontmostPID },
            emit: {
                emitted.append($0)
                return emitSucceeds
            },
            diagnostics: { diagnostics.append($0) }
        )
        coordinator.onTerminal = { terminals.append($0) }

        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: "com.example.chat"
        )
        precondition(coordinator.isCountingDown)
        precondition(presenter.shown.last?.remainingSeconds == 1)

        now = 100.5
        scheduler.fireAll()
        precondition(emitted.isEmpty)
        precondition(
            abs((presenter.updated.last?.remainingSeconds ?? 0) - 0.5) < 0.001
        )

        now = 101
        scheduler.fireAll()
        precondition(emitted == [.returnKey])
        precondition(terminals.last == .emitted)
        precondition(!coordinator.isCountingDown)
        scheduler.fireAll()
        precondition(emitted.count == 1)

        durationSeconds = 2
        now = 200
        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        presenter.clickCancel()
        precondition(terminals.last == .cancelled(.cancelButton))
        precondition(emitted.count == 1)

        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        precondition(coordinator.cancel(reason: .escapeKey))
        precondition(terminals.last == .cancelled(.escapeKey))
        precondition(!coordinator.cancel(reason: .escapeKey))

        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        precondition(coordinator.cancel(reason: .rightMouseButton))
        precondition(terminals.last == .cancelled(.rightMouseButton))
        precondition(!coordinator.isCountingDown)

        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        precondition(coordinator.cancel(reason: .manualSubmitKey))
        precondition(terminals.last == .cancelled(.manualSubmitKey))
        now = 202
        scheduler.fireAll()
        precondition(emitted.count == 1)

        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        coordinator.schedule(
            action: .commandReturn,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        precondition(terminals.contains(.cancelled(.replaced)))
        now = 204
        scheduler.fireAll()
        precondition(emitted.last == .commandReturn)
        precondition(emitted.count == 2)

        now = 300
        frontmostPID = 99
        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        now = 302
        scheduler.fireAll()
        precondition(terminals.last == .skipped(.focusChanged))
        precondition(emitted.count == 2)

        now = 400
        frontmostPID = 42
        emitSucceeds = false
        coordinator.schedule(
            action: .returnKey,
            taskID: UUID(),
            targetPID: 42,
            targetBundleIdentifier: nil
        )
        now = 402
        scheduler.fireAll()
        precondition(terminals.last == .skipped(.eventEmissionFailed))
        precondition(emitted.count == 3)
        precondition(diagnostics.contains { $0.contains("countdown_started") })
        precondition(diagnostics.contains { $0.contains("countdown_terminal") })
        print("AutoSendCountdownCoordinatorCheck passed")
    }
}
