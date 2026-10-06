import Foundation

@main
struct PreviewRequestSchedulerCheck {
    static func main() {
        let sessionID = UUID()
        let policy = PreviewSchedulingPolicy(
            fastDeadlineSeconds: 0.7,
            maxConsecutiveFastRequests: 4,
            correctionBacklogThreshold: 2,
            backlogMaxConsecutiveFastRequests: 1
        )
        var scheduler = PreviewRequestScheduler(sessionID: sessionID, epoch: 1, policy: policy)
        let fast1 = request(sessionID: sessionID, epoch: 1, lane: .fast, chunkID: 0, enqueuedUptime: 10.0)
        let fast2 = request(sessionID: sessionID, epoch: 1, lane: .fast, chunkID: 0, enqueuedUptime: 10.1)
        let correction1 = request(sessionID: sessionID, epoch: 1, lane: .correction, chunkID: 0, enqueuedUptime: 10.2)
        let correction2 = request(sessionID: sessionID, epoch: 1, lane: .correction, chunkID: 1, enqueuedUptime: 10.3)
        let stopTail = request(sessionID: sessionID, epoch: 1, lane: .stopTail, chunkID: 2, enqueuedUptime: 10.4)

        precondition(scheduler.enqueueFast(fast1) == fast1)
        precondition(scheduler.activeRequest == fast1)
        precondition(scheduler.enqueueFast(fast2) == nil)
        precondition(scheduler.pendingFastRequest == fast2, "latest fast request must replace the older pending request")
        let fast3 = request(sessionID: sessionID, epoch: 1, lane: .fast, chunkID: 0, enqueuedUptime: 10.2)
        _ = scheduler.enqueueFast(fast3)
        precondition(scheduler.takeDiscardedRequests() == [fast2], "replaced fast snapshot must be returned for file cleanup")

        precondition(scheduler.enqueueCorrection(correction1) == nil)
        precondition(scheduler.pendingCorrectionCount == 1)

        precondition(
            scheduler.complete(requestID: fast1.requestID, completedAt: 11.0) == fast3,
            "a fast request waiting beyond its deadline must outrank queued correction"
        )
        precondition(scheduler.complete(requestID: fast3.requestID, completedAt: 11.1) == correction1)

        precondition(scheduler.enqueueCorrection(correction2) == nil)
        precondition(scheduler.beginStopFinalization(stopTail) == nil)
        precondition(scheduler.complete(requestID: correction1.requestID, completedAt: 11.2) == stopTail, "stop tail must outrank queued correction")
        precondition(scheduler.complete(requestID: stopTail.requestID, completedAt: 11.3) == correction2)
        precondition(scheduler.complete(requestID: correction2.requestID, completedAt: 11.4) == nil)

        scheduler.reset(epoch: 2)
        let activeCorrection = request(sessionID: sessionID, epoch: 2, lane: .correction, chunkID: 3, enqueuedUptime: 20.0)
        let nextCorrection = request(sessionID: sessionID, epoch: 2, lane: .correction, chunkID: 4, enqueuedUptime: 20.1)
        let waitingFast = request(sessionID: sessionID, epoch: 2, lane: .fast, chunkID: 4, enqueuedUptime: 20.2)
        _ = scheduler.enqueueCorrection(activeCorrection)
        _ = scheduler.enqueueCorrection(nextCorrection)
        _ = scheduler.enqueueFast(waitingFast)
        precondition(
            scheduler.complete(requestID: activeCorrection.requestID, completedAt: 20.3) == waitingFast,
            "two corrections must not run consecutively ahead of a waiting fast request"
        )

        scheduler.reset(epoch: 3)
        let fairnessCorrection = request(sessionID: sessionID, epoch: 3, lane: .correction, chunkID: 5, enqueuedUptime: 30.1)
        var activeFast = request(sessionID: sessionID, epoch: 3, lane: .fast, chunkID: 5, enqueuedUptime: 30.0)
        _ = scheduler.enqueueFast(activeFast)
        _ = scheduler.enqueueCorrection(fairnessCorrection)
        for index in 1...4 {
            let nextFast = request(
                sessionID: sessionID,
                epoch: 3,
                lane: .fast,
                chunkID: 5,
                enqueuedUptime: 30.0 + Double(index) * 0.1
            )
            _ = scheduler.enqueueFast(nextFast)
            let selected = scheduler.complete(
                requestID: activeFast.requestID,
                completedAt: 31.0 + Double(index)
            )
            if index < 4 {
                precondition(selected == nextFast)
                activeFast = nextFast
            } else {
                precondition(
                    selected == fairnessCorrection,
                    "correction must run after four consecutive fast completions even when pending fast is overdue"
                )
            }
        }

        var pressureScheduler = PreviewRequestScheduler(sessionID: sessionID, epoch: 1, policy: policy)
        let pressureActiveFast = request(sessionID: sessionID, epoch: 1, lane: .fast, chunkID: 6, enqueuedUptime: 40.0)
        let pressureWaitingFast = request(sessionID: sessionID, epoch: 1, lane: .fast, chunkID: 6, enqueuedUptime: 40.1)
        let pressureCorrection1 = request(sessionID: sessionID, epoch: 1, lane: .correction, chunkID: 6, enqueuedUptime: 40.2)
        let pressureCorrection2 = request(sessionID: sessionID, epoch: 1, lane: .correction, chunkID: 7, enqueuedUptime: 40.3)
        _ = pressureScheduler.enqueueFast(pressureActiveFast)
        _ = pressureScheduler.enqueueFast(pressureWaitingFast)
        _ = pressureScheduler.enqueueCorrection(pressureCorrection1)
        _ = pressureScheduler.enqueueCorrection(pressureCorrection2)
        precondition(
            pressureScheduler.complete(requestID: pressureActiveFast.requestID, completedAt: 41.0) == pressureCorrection1,
            "a correction backlog of two must tighten fairness to one fast per correction"
        )
        precondition(
            pressureScheduler.complete(requestID: pressureCorrection1.requestID, completedAt: 41.1) == pressureWaitingFast,
            "backlog pressure must still yield one fast request after correction"
        )

        let stale = request(sessionID: sessionID, epoch: 0, lane: .correction, chunkID: 8, enqueuedUptime: 50.0)
        precondition(scheduler.enqueueCorrection(stale) == nil)

        scheduler.reset(epoch: 4)
        precondition(scheduler.epoch == 4)
        precondition(scheduler.pendingCorrectionCount == 0)
        precondition(scheduler.pendingFastRequest == nil)

        let active = request(sessionID: sessionID, epoch: 4, lane: .fast, chunkID: 7, enqueuedUptime: 50.0)
        let queuedFast = request(sessionID: sessionID, epoch: 4, lane: .fast, chunkID: 7, enqueuedUptime: 50.1)
        let queuedCorrection = request(sessionID: sessionID, epoch: 4, lane: .correction, chunkID: 7, enqueuedUptime: 50.2)
        let queuedStopTail = request(sessionID: sessionID, epoch: 4, lane: .stopTail, chunkID: 7, enqueuedUptime: 50.3)
        _ = scheduler.enqueueFast(active)
        _ = scheduler.enqueueFast(queuedFast)
        _ = scheduler.enqueueCorrection(queuedCorrection)
        _ = scheduler.beginStopFinalization(queuedStopTail)
        let discarded = scheduler.cancelAll()
        precondition(
            Set(discarded.map(\.requestID)) == Set([active.requestID, queuedFast.requestID, queuedCorrection.requestID, queuedStopTail.requestID]),
            "deadline cancellation must return active and queued requests, including stopTail, for file cleanup"
        )
        precondition(scheduler.complete(requestID: active.requestID, completedAt: 50.3) == nil)

        scheduler.reset(epoch: 5)
        let drainActive = request(sessionID: sessionID, epoch: 5, lane: .fast, chunkID: 8, enqueuedUptime: 60.0)
        let drainFast = request(sessionID: sessionID, epoch: 5, lane: .fast, chunkID: 8, enqueuedUptime: 60.1)
        let drainCorrection = request(sessionID: sessionID, epoch: 5, lane: .correction, chunkID: 8, enqueuedUptime: 60.2)
        _ = scheduler.enqueueFast(drainActive)
        _ = scheduler.enqueueFast(drainFast)
        _ = scheduler.enqueueCorrection(drainCorrection)
        let stopDiscarded = scheduler.prepareForCorrectionDrain()
        precondition(stopDiscarded == [drainFast])
        precondition(scheduler.complete(requestID: drainActive.requestID, completedAt: 60.3) == drainCorrection)
        precondition(scheduler.complete(requestID: drainCorrection.requestID, completedAt: 60.4) == nil)
        precondition(scheduler.isIdle)

        print("PreviewRequestSchedulerCheck passed")
    }

    private static func request(
        sessionID: UUID,
        epoch: Int,
        lane: PreviewSourceLane,
        chunkID: Int,
        enqueuedUptime: TimeInterval
    ) -> PreviewPipelineRequest {
        PreviewPipelineRequest(
            sessionID: sessionID,
            epoch: epoch,
            requestID: UUID(),
            chunkID: chunkID,
            lane: lane,
            audioURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).wav"),
            audioRange: PreviewAudioRange(start: 0, end: 15),
            boundary: nil,
            enqueuedUptime: enqueuedUptime
        )
    }
}
