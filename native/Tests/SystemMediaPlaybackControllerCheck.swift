import AppKit
import ApplicationServices
import Foundation

private final class ManualMediaStateProvider: SystemMediaPlaybackStateProviding {
    private var completions: [(SystemMediaPlaybackSnapshot) -> Void] = []
    private(set) var requestCount = 0

    var pendingCount: Int { completions.count }

    func fetchSnapshot(
        completion: @escaping (SystemMediaPlaybackSnapshot) -> Void
    ) {
        requestCount += 1
        completions.append(completion)
    }

    func resolveNext(_ snapshot: SystemMediaPlaybackSnapshot) {
        precondition(!completions.isEmpty, "expected a pending media-state query")
        completions.removeFirst()(snapshot)
    }
}

private final class ManualMediaScheduler {
    private(set) var scheduledCount = 0
    private var workItems: [DispatchWorkItem] = []

    func schedule(after _: TimeInterval, _ workItem: DispatchWorkItem) {
        scheduledCount += 1
        workItems.append(workItem)
    }

    func runNext() {
        precondition(!workItems.isEmpty, "expected a pending scheduled action")
        workItems.removeFirst().perform()
    }

    func runAll() {
        let pending = workItems
        workItems.removeAll()
        pending.forEach { $0.perform() }
    }
}

@main
struct SystemMediaPlaybackControllerCheck {
    static func main() {
        pausedAndUnknownStartsNeverEmit()
        playingMediaResumesOnlyForTheSamePausedProcess()
        userResumedOrReplacementMediaNeverToggleAtCleanup()
        lateAndSupersededStartQueriesAreIgnored()
        failedPauseEmissionNeverCreatesResumeOwnership()
        coalescesConsecutiveRecordings()
        disabledStartAndDuplicateCleanupAreNoOps()
        generatedEventsCarryIsolationMarker()
        print("SystemMediaPlaybackControllerCheck passed")
    }

    private static func pausedAndUnknownStartsNeverEmit() {
        for snapshot in [
            SystemMediaPlaybackSnapshot(state: .paused, processID: 101),
            .unknown
        ] {
            let provider = ManualMediaStateProvider()
            let scheduler = ManualMediaScheduler()
            var emissionCount = 0
            let controller = makeController(
                provider: provider,
                scheduler: scheduler
            ) {
                emissionCount += 1
                return true
            }

            controller.pauseIfNeeded(enabled: true)
            precondition(emissionCount == 0, "state query must precede media control")
            provider.resolveNext(snapshot)
            controller.resume()
            scheduler.runAll()

            precondition(emissionCount == 0, "paused or unknown media must remain unchanged")
            precondition(provider.requestCount == 1, "unowned cleanup must not query again")
        }
    }

    private static func playingMediaResumesOnlyForTheSamePausedProcess() {
        let provider = ManualMediaStateProvider()
        let scheduler = ManualMediaScheduler()
        var emissionCount = 0
        let controller = makeController(provider: provider, scheduler: scheduler) {
            emissionCount += 1
            return true
        }

        controller.pauseIfNeeded(enabled: true)
        provider.resolveNext(.init(state: .playing, processID: 202))
        precondition(emissionCount == 1, "confirmed playing media must be paused once")

        controller.resume()
        controller.resume()
        precondition(scheduler.scheduledCount == 1, "duplicate cleanup must schedule once")
        scheduler.runNext()
        precondition(provider.pendingCount == 1, "resume must re-check playback state")
        provider.resolveNext(.init(state: .paused, processID: 202))

        precondition(emissionCount == 2, "same paused process must resume once")
    }

    private static func userResumedOrReplacementMediaNeverToggleAtCleanup() {
        for cleanupSnapshot in [
            SystemMediaPlaybackSnapshot(state: .playing, processID: 303),
            SystemMediaPlaybackSnapshot(state: .paused, processID: 404),
            .unknown
        ] {
            let provider = ManualMediaStateProvider()
            let scheduler = ManualMediaScheduler()
            var emissionCount = 0
            let controller = makeController(
                provider: provider,
                scheduler: scheduler
            ) {
                emissionCount += 1
                return true
            }

            controller.pauseIfNeeded(enabled: true)
            provider.resolveNext(.init(state: .playing, processID: 303))
            controller.resume()
            scheduler.runNext()
            provider.resolveNext(cleanupSnapshot)

            precondition(
                emissionCount == 1,
                "user-resumed, replacement, or unknown media must not receive a cleanup toggle"
            )
        }
    }

    private static func lateAndSupersededStartQueriesAreIgnored() {
        do {
            let provider = ManualMediaStateProvider()
            let scheduler = ManualMediaScheduler()
            var emissionCount = 0
            let controller = makeController(
                provider: provider,
                scheduler: scheduler
            ) {
                emissionCount += 1
                return true
            }

            controller.pauseIfNeeded(enabled: true)
            controller.resume()
            provider.resolveNext(.init(state: .playing, processID: 505))
            precondition(emissionCount == 0, "late start callback must not pause after cleanup")
        }

        do {
            let provider = ManualMediaStateProvider()
            let scheduler = ManualMediaScheduler()
            var emissionCount = 0
            let controller = makeController(
                provider: provider,
                scheduler: scheduler
            ) {
                emissionCount += 1
                return true
            }

            controller.pauseIfNeeded(enabled: true)
            controller.pauseIfNeeded(enabled: true)
            precondition(provider.pendingCount == 2)
            provider.resolveNext(.init(state: .playing, processID: 606))
            precondition(emissionCount == 0, "superseded start query must be ignored")
            provider.resolveNext(.init(state: .playing, processID: 606))
            precondition(emissionCount == 1, "current start query may pause confirmed media")
        }
    }

    private static func failedPauseEmissionNeverCreatesResumeOwnership() {
        let provider = ManualMediaStateProvider()
        let scheduler = ManualMediaScheduler()
        var emissionAttempts = 0
        let controller = makeController(provider: provider, scheduler: scheduler) {
            emissionAttempts += 1
            return false
        }

        controller.pauseIfNeeded(enabled: true)
        provider.resolveNext(.init(state: .playing, processID: 707))
        controller.resume()
        scheduler.runAll()

        precondition(emissionAttempts == 1)
        precondition(scheduler.scheduledCount == 0, "failed pause must not own a resume")
    }

    private static func coalescesConsecutiveRecordings() {
        let provider = ManualMediaStateProvider()
        let scheduler = ManualMediaScheduler()
        var emissionCount = 0
        let controller = makeController(provider: provider, scheduler: scheduler) {
            emissionCount += 1
            return true
        }

        controller.pauseIfNeeded(enabled: true)
        provider.resolveNext(.init(state: .playing, processID: 808))
        controller.resume()
        controller.pauseIfNeeded(enabled: true)
        scheduler.runAll()

        precondition(emissionCount == 1, "consecutive recording must cancel intermediate resume")
        precondition(provider.requestCount == 1, "owned consecutive recording must not re-query start")

        controller.resume()
        scheduler.runNext()
        provider.resolveNext(.init(state: .paused, processID: 808))
        precondition(emissionCount == 2, "final cleanup must resume the owned process once")
    }

    private static func disabledStartAndDuplicateCleanupAreNoOps() {
        let provider = ManualMediaStateProvider()
        let scheduler = ManualMediaScheduler()
        var emissionCount = 0
        let controller = makeController(provider: provider, scheduler: scheduler) {
            emissionCount += 1
            return true
        }

        controller.pauseIfNeeded(enabled: false)
        controller.resume()
        controller.resume()
        scheduler.runAll()

        precondition(provider.requestCount == 0)
        precondition(emissionCount == 0)
    }

    private static func generatedEventsCarryIsolationMarker() {
        guard let events = SyntheticMediaKeyEvent.makePlayPauseEvents() else {
            preconditionFailure("system play/pause events must be constructible")
        }
        precondition(events.count == 2, "one toggle must contain key down and key up")
        precondition(
            events.allSatisfy(SyntheticMediaKeyEvent.isTypeWhaleGenerated),
            "both events must carry the TypeWhale marker"
        )

        guard let physicalLikeEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ) else {
            preconditionFailure("test event must be constructible")
        }
        precondition(
            !SyntheticMediaKeyEvent.isTypeWhaleGenerated(physicalLikeEvent),
            "unmarked physical events must not be ignored"
        )
    }

    private static func makeController(
        provider: SystemMediaPlaybackStateProviding,
        scheduler: ManualMediaScheduler,
        emitPlayPause: @escaping () -> Bool
    ) -> SystemMediaPlaybackController {
        SystemMediaPlaybackController(
            stateProvider: provider,
            resumeDelay: 1,
            emitPlayPause: emitPlayPause,
            schedule: scheduler.schedule,
            log: { _ in }
        )
    }
}
