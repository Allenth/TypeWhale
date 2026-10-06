import Foundation

enum PreviewBoundaryKind: String, Codable, Sendable {
    case voicePause
    case hardLimit
}

struct PreviewBoundary: Equatable, Codable, Sendable {
    let sessionID: UUID
    let chunkID: Int
    let time: TimeInterval
    let kind: PreviewBoundaryKind
}

struct PreviewWindowPlan: Equatable, Sendable {
    let boundary: PreviewBoundary
    let audioRange: PreviewAudioRange
    let recovery: Bool

    var containsBoundaryInCenterSafeRegion: Bool {
        let guardDuration = audioRange.duration / 4
        return boundary.time >= audioRange.start + guardDuration
            && boundary.time <= audioRange.end - guardDuration
    }
}

struct BoundaryCenteredPreviewPlanner: Sendable {
    let softBoundarySeconds: TimeInterval = 10
    let hardBoundarySeconds: TimeInterval = 18
    let correctionWindowSeconds: TimeInterval = 22.5
    let recoveryWindowSeconds: TimeInterval = 22.5

    func proposeBoundary(
        sessionID: UUID,
        chunkID: Int,
        chunkStartedAt: TimeInterval,
        capturedAt: TimeInterval,
        voiceActive: Bool
    ) -> PreviewBoundary? {
        let chunkDuration = capturedAt - chunkStartedAt
        if chunkDuration >= hardBoundarySeconds {
            return PreviewBoundary(sessionID: sessionID, chunkID: chunkID, time: capturedAt, kind: .hardLimit)
        }
        if chunkDuration >= softBoundarySeconds, !voiceActive {
            return PreviewBoundary(sessionID: sessionID, chunkID: chunkID, time: capturedAt, kind: .voicePause)
        }
        return nil
    }

    func correctionWindow(
        around boundary: PreviewBoundary,
        sessionStart: TimeInterval,
        availableAudioEnd: TimeInterval,
        recovery: Bool
    ) -> PreviewWindowPlan? {
        let targetDuration = recovery ? recoveryWindowSeconds : correctionWindowSeconds
        let half = targetDuration / 2
        let start = max(sessionStart, boundary.time - half)
        let desiredEnd = start + targetDuration
        guard availableAudioEnd >= desiredEnd else { return nil }
        return PreviewWindowPlan(
            boundary: boundary,
            audioRange: PreviewAudioRange(start: start, end: desiredEnd),
            recovery: recovery
        )
    }
}
