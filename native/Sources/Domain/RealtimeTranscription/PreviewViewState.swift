import Foundation

struct PreviewViewState: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let sequence: UInt64
    let stableCharacterCount: Int
    let stableWindowText: String
    let volatileTailText: String
    let lifecycle: TranscriptionLifecycle
    let failure: TranscriptionFailure?

    var displayText: String {
        stableWindowText + volatileTailText
    }
}
