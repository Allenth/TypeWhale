enum FinalRecognitionAuthorityPolicy {
    enum Action: Equatable {
        case useRealtimeCache
        case realtimeCacheUnavailable
        case runSelectedBackend
    }

    static func action(
        backend: ASRBackend,
        reRecognizeWholeRecordingAfterStop: Bool,
        realtimeCacheReady: Bool
    ) -> Action {
        guard backend == .senseVoice else {
            return .runSelectedBackend
        }
        guard !reRecognizeWholeRecordingAfterStop else {
            return .runSelectedBackend
        }
        return realtimeCacheReady ? .useRealtimeCache : .realtimeCacheUnavailable
    }
}
