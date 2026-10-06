import Foundation

@main
struct TranscriptionProviderEventContractCheck {
    static func main() {
        textEventsAreExplicitlySeparatedFromTerminalAndDiagnosticEvents()
        terminalEventsAreExplicitlySeparatedFromTextEvents()
        connectionEventsRemainDiagnosticOnly()
        print("TranscriptionProviderEventContractCheck passed")
    }

    private static func textEventsAreExplicitlySeparatedFromTerminalAndDiagnosticEvents() {
        precondition(contract(.partial(metadata(1), segmentID: "tail", revision: 1, text: "今天")) == "text_output")
        precondition(contract(.finalized(metadata(2), segment: segment("s1", text: "今天讨论"))) == "text_output")
        precondition(contract(.reconciled(
            metadata(3),
            finalizedSegments: [segment("s1", text: "今天讨论")],
            volatileSegmentID: "tail",
            revision: 2,
            text: "在线模型"
        )) == "text_output")
    }

    private static func terminalEventsAreExplicitlySeparatedFromTextEvents() {
        let failure = TranscriptionFailure(
            code: .transportDisconnected,
            message: "offline",
            isRecoverable: false
        )

        precondition(contract(.completed(metadata(4))) == "terminal")
        precondition(contract(.failed(metadata(5), failure)) == "terminal")
        precondition(contract(.cancelled(metadata(6))) == "terminal")
    }

    private static func connectionEventsRemainDiagnosticOnly() {
        precondition(contract(.connectionChanged(metadata(7), .connected)) == "diagnostic")
    }

    private static func contract(_ event: TranscriptionEvent) -> String {
        TranscriptionProviderEventContract.classify(event).rawValue
    }

    private static func metadata(_ sequence: UInt64) -> TranscriptionEventMetadata {
        TranscriptionEventMetadata(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1,
            sequence: sequence,
            emittedAtUptime: TimeInterval(sequence)
        )
    }

    private static func segment(_ id: String, text: String) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            audioRange: TranscriptionAudioRange(start: 0, end: 1)
        )
    }
}
