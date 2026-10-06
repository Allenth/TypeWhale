import Foundation

enum RealtimeBoundaryKind: Equatable, Sendable {
    case voicePause
    case hardLimit
    case conflictRecovery
}

struct RealtimeBoundaryCorrectionPlan: Equatable, Sendable {
    let boundaryTime: TimeInterval
    let audioStartTime: TimeInterval
    let audioEndTime: TimeInterval
    let kind: RealtimeBoundaryKind
}

struct RealtimeBoundaryCorrectionPlanner: Sendable {
    let preRollSeconds: TimeInterval
    let postRollSeconds: TimeInterval

    func plan(
        boundaryTime: TimeInterval,
        availableAudioStart: TimeInterval,
        availableAudioEnd: TimeInterval,
        kind: RealtimeBoundaryKind
    ) -> RealtimeBoundaryCorrectionPlan? {
        guard boundaryTime.isFinite,
              availableAudioStart.isFinite,
              availableAudioEnd.isFinite,
              availableAudioEnd >= availableAudioStart else {
            return nil
        }
        let preRoll = max(0, preRollSeconds)
        let postRoll = max(0, postRollSeconds)
        let requiredEnd = boundaryTime + postRoll
        guard availableAudioEnd >= requiredEnd else { return nil }

        let start = max(availableAudioStart, boundaryTime - preRoll)
        let end = min(availableAudioEnd, requiredEnd)
        guard end > start else { return nil }
        return RealtimeBoundaryCorrectionPlan(
            boundaryTime: boundaryTime,
            audioStartTime: start,
            audioEndTime: end,
            kind: kind
        )
    }
}
