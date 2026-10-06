import Foundation

struct TranscriptionEventMetadata: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let sequence: UInt64
    let emittedAtUptime: TimeInterval
}

enum TranscriptionFailureCode: String, Equatable, Sendable {
    case providerUnavailable
    case providerRejectedInput
    case subscriberOverflow
    case transportDisconnected
    case internalInvariant
}

struct TranscriptionFailure: Equatable, Sendable {
    let code: TranscriptionFailureCode
    let message: String
    let isRecoverable: Bool
}

enum ProviderConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

enum TranscriptionEvent: Equatable, Sendable {
    case partial(
        TranscriptionEventMetadata,
        segmentID: String,
        revision: Int,
        text: String
    )
    case finalized(
        TranscriptionEventMetadata,
        segment: TranscriptSegment
    )
    case reconciled(
        TranscriptionEventMetadata,
        finalizedSegments: [TranscriptSegment],
        volatileSegmentID: String,
        revision: Int,
        text: String
    )
    case failed(
        TranscriptionEventMetadata,
        TranscriptionFailure
    )
    case connectionChanged(
        TranscriptionEventMetadata,
        ProviderConnectionState
    )
    case completed(TranscriptionEventMetadata)
    case cancelled(TranscriptionEventMetadata)

    var metadata: TranscriptionEventMetadata {
        switch self {
        case .partial(let metadata, _, _, _),
             .finalized(let metadata, _),
             .reconciled(let metadata, _, _, _, _),
             .failed(let metadata, _),
             .connectionChanged(let metadata, _),
             .completed(let metadata),
             .cancelled(let metadata):
            return metadata
        }
    }
}
