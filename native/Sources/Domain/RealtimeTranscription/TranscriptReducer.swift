import Foundation

struct TranscriptReducer: Sendable {
    private(set) var state: TranscriptState

    init(sessionID: TranscriptionSessionID, providerEpoch: Int) {
        state = .initial(sessionID: sessionID, providerEpoch: providerEpoch)
    }

    init(migrating state: TranscriptState, toProviderEpoch providerEpoch: Int) {
        self.state = TranscriptState(
            sessionID: state.sessionID,
            providerEpoch: providerEpoch,
            lastSequence: 0,
            confirmedSegments: state.confirmedSegments,
            volatileSegmentID: nil,
            volatileRevision: 0,
            volatileText: "",
            lifecycle: .running,
            failure: nil,
            connectionState: .disconnected
        )
    }

    mutating func apply(_ event: TranscriptionEvent) -> TranscriptState? {
        let metadata = event.metadata
        guard metadata.sessionID == state.sessionID,
              metadata.providerEpoch == state.providerEpoch,
              metadata.sequence > state.lastSequence,
              !state.lifecycle.isTerminal else {
            return nil
        }

        let updated: TranscriptState?
        switch event {
        case .partial(_, let segmentID, let revision, let text):
            updated = applyPartial(
                metadata: metadata,
                segmentID: segmentID,
                revision: revision,
                text: text
            )

        case .finalized(_, let segment):
            updated = applyFinalized(metadata: metadata, segment: segment)

        case .reconciled(
            _,
            let finalizedSegments,
            let volatileSegmentID,
            let revision,
            let text
        ):
            updated = applyReconciled(
                metadata: metadata,
                finalizedSegments: finalizedSegments,
                volatileSegmentID: volatileSegmentID,
                revision: revision,
                text: text
            )

        case .failed(_, let failure):
            updated = replacing(
                lastSequence: metadata.sequence,
                lifecycle: failure.isRecoverable ? .running : .failed,
                failure: failure
            )

        case .connectionChanged(_, let connectionState):
            updated = replacing(
                lastSequence: metadata.sequence,
                preservesFailure: true,
                connectionState: connectionState
            )

        case .completed:
            updated = replacing(
                lastSequence: metadata.sequence,
                lifecycle: .completed,
                preservesFailure: true
            )

        case .cancelled:
            updated = replacing(
                lastSequence: metadata.sequence,
                lifecycle: .cancelled,
                preservesFailure: true
            )
        }

        guard let updated else { return nil }
        state = updated
        return state
    }

    private func applyPartial(
        metadata: TranscriptionEventMetadata,
        segmentID: String,
        revision: Int,
        text: String
    ) -> TranscriptState? {
        guard revision > 0,
              !state.confirmedSegments.contains(where: { $0.id == segmentID }) else {
            return nil
        }
        if state.volatileSegmentID == segmentID,
           revision <= state.volatileRevision {
            return nil
        }
        return replacing(
            lastSequence: metadata.sequence,
            volatileSegmentID: segmentID,
            preservesVolatileSegmentID: false,
            volatileRevision: revision,
            volatileText: text,
            failure: nil
        )
    }

    private func applyFinalized(
        metadata: TranscriptionEventMetadata,
        segment: TranscriptSegment
    ) -> TranscriptState? {
        guard !state.confirmedSegments.contains(where: { $0.id == segment.id }) else {
            return nil
        }
        var segments = state.confirmedSegments
        segments.append(segment)
        let finalizesVolatile = state.volatileSegmentID == segment.id
        return replacing(
            lastSequence: metadata.sequence,
            confirmedSegments: segments,
            volatileSegmentID: finalizesVolatile ? nil : state.volatileSegmentID,
            preservesVolatileSegmentID: false,
            volatileRevision: finalizesVolatile ? 0 : state.volatileRevision,
            volatileText: finalizesVolatile ? "" : state.volatileText,
            failure: nil
        )
    }

    private func applyReconciled(
        metadata: TranscriptionEventMetadata,
        finalizedSegments: [TranscriptSegment],
        volatileSegmentID: String,
        revision: Int,
        text: String
    ) -> TranscriptState? {
        guard revision > 0,
              !state.confirmedSegments.contains(where: { $0.id == volatileSegmentID }) else {
            return nil
        }
        if state.volatileSegmentID == volatileSegmentID,
           revision <= state.volatileRevision {
            return nil
        }

        var knownIDs = Set(state.confirmedSegments.map(\.id))
        var segments = state.confirmedSegments
        for segment in finalizedSegments where knownIDs.insert(segment.id).inserted {
            segments.append(segment)
        }
        return replacing(
            lastSequence: metadata.sequence,
            confirmedSegments: segments,
            volatileSegmentID: volatileSegmentID,
            preservesVolatileSegmentID: false,
            volatileRevision: revision,
            volatileText: text,
            failure: nil
        )
    }

    private func replacing(
        lastSequence: UInt64,
        confirmedSegments: [TranscriptSegment]? = nil,
        volatileSegmentID: String? = nil,
        preservesVolatileSegmentID: Bool = true,
        volatileRevision: Int? = nil,
        volatileText: String? = nil,
        lifecycle: TranscriptionLifecycle? = nil,
        failure: TranscriptionFailure? = nil,
        preservesFailure: Bool = false,
        connectionState: ProviderConnectionState? = nil
    ) -> TranscriptState {
        TranscriptState(
            sessionID: state.sessionID,
            providerEpoch: state.providerEpoch,
            lastSequence: lastSequence,
            confirmedSegments: confirmedSegments ?? state.confirmedSegments,
            volatileSegmentID: preservesVolatileSegmentID ? state.volatileSegmentID : volatileSegmentID,
            volatileRevision: volatileRevision ?? state.volatileRevision,
            volatileText: volatileText ?? state.volatileText,
            lifecycle: lifecycle ?? state.lifecycle,
            failure: preservesFailure ? state.failure : failure,
            connectionState: connectionState ?? state.connectionState
        )
    }
}
