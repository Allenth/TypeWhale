import Foundation

enum PreviewStateProjector {
    static func project(
        _ state: TranscriptState,
        visibleCharacterLimit: Int = 160
    ) -> PreviewViewState {
        let limit = max(1, visibleCharacterLimit)
        let volatileTail = String(state.volatileText.suffix(limit))
        let stableCapacity = max(0, limit - volatileTail.count)
        let stableWindow = String(state.confirmedText.suffix(stableCapacity))

        return PreviewViewState(
            sessionID: state.sessionID,
            providerEpoch: state.providerEpoch,
            sequence: state.lastSequence,
            stableCharacterCount: state.confirmedText.count,
            stableWindowText: stableWindow,
            volatileTailText: volatileTail,
            lifecycle: state.lifecycle,
            failure: state.failure
        )
    }
}
