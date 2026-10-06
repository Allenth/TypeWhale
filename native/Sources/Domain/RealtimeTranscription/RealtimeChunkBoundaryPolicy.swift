import Foundation

struct RealtimeChunkBoundaryPolicy: Equatable, Sendable {
    let firstChunkSoftSeconds: TimeInterval
    let laterChunkSoftSeconds: TimeInterval
    let hardSeconds: TimeInterval

    init(
        firstChunkSoftSeconds: TimeInterval = 6,
        laterChunkSoftSeconds: TimeInterval = 10,
        hardSeconds: TimeInterval = 18
    ) {
        self.firstChunkSoftSeconds = firstChunkSoftSeconds
        self.laterChunkSoftSeconds = laterChunkSoftSeconds
        self.hardSeconds = hardSeconds
    }

    func hasReachedHardBoundary(_ chunkDuration: TimeInterval) -> Bool {
        chunkDuration >= hardSeconds
    }

    func shouldFinalize(
        chunkIndex: Int,
        chunkDuration: TimeInterval,
        voiceActive: Bool,
        hasObservedVoice: Bool
    ) -> Bool {
        if hasReachedHardBoundary(chunkDuration) {
            return true
        }
        let softSeconds = chunkIndex == 0 ? firstChunkSoftSeconds : laterChunkSoftSeconds
        guard chunkDuration >= softSeconds, !voiceActive else {
            return false
        }
        return chunkIndex > 0 || hasObservedVoice
    }
}
