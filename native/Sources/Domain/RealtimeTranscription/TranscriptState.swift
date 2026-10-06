import Foundation

enum TranscriptionLifecycle: Equatable, Sendable {
    case running
    case completed
    case cancelled
    case failed

    var isTerminal: Bool {
        switch self {
        case .running:
            return false
        case .completed, .cancelled, .failed:
            return true
        }
    }
}

struct TranscriptState: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let lastSequence: UInt64
    let confirmedSegments: [TranscriptSegment]
    let volatileSegmentID: String?
    let volatileRevision: Int
    let volatileText: String
    let lifecycle: TranscriptionLifecycle
    let failure: TranscriptionFailure?
    let connectionState: ProviderConnectionState

    var confirmedText: String {
        confirmedSegments.map(\.text).joined()
    }

    static func initial(
        sessionID: TranscriptionSessionID,
        providerEpoch: Int
    ) -> TranscriptState {
        TranscriptState(
            sessionID: sessionID,
            providerEpoch: providerEpoch,
            lastSequence: 0,
            confirmedSegments: [],
            volatileSegmentID: nil,
            volatileRevision: 0,
            volatileText: "",
            lifecycle: .running,
            failure: nil,
            connectionState: .disconnected
        )
    }
}
