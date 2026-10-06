import Foundation

@main
struct RealtimeTranscriptTraceCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "typewhale-realtime-trace-check-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let trace = RealtimeTranscriptTrace(
            sessionID: sessionID,
            directoryURL: root,
            maximumRecordsPerSession: 4,
            maximumRetainedSessions: 2,
            developerTextSessionID: nil
        )
        let result = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 1,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 18),
            text: "这段正文不能写入生产追踪",
            tokens: [],
            tokenTimestamps: nil
        )
        let state = PreviewTranscriptState(
            confirmedSegments: [],
            mutableTailText: result.text,
            displayText: result.text,
            displayRevision: 1,
            recoveryRequested: false,
            confirmedCharacterCount: 0
        )
        let transition = PreviewOwnershipTransition(
            decision: .correctionMerged,
            replacementRange: PreviewAudioRange(start: 7, end: 29),
            confirmedRange: PreviewAudioRange(start: 7, end: 18),
            confirmedThroughTime: 18,
            promotedFastCharacterCount: 3,
            promotedFastRange: PreviewAudioRange(start: 1.1, end: 5.6),
            promotedFastText: "开头保",
            removedFastChunkIDs: [0]
        )

        for _ in 0..<5 {
            trace.recordMerge(
                result: result,
                transition: transition,
                confirmedCharacterCount: state.confirmedCharacterCount,
                volatileCharacterCount: state.mutableTailText.count
            )
        }
        trace.flushForTesting()

        let records = try trace.readRecordsForTesting()
        precondition(records.count <= 4, "per-session trace retention must be bounded")
        precondition(records.map(\.sequence) == [4, 5], "compaction must preserve deterministic tail order")
        precondition(records.allSatisfy { $0.audioRange == result.audioRange })
        precondition(records.allSatisfy { $0.textCharacterCount == result.text.count })
        precondition(records.allSatisfy { !$0.textHash.isEmpty })
        precondition(records.allSatisfy { $0.confirmedRange == transition.confirmedRange })
        precondition(records.allSatisfy { $0.promotedFastRange == transition.promotedFastRange })
        precondition(records.allSatisfy { $0.promotedFastTextHash?.isEmpty == false })
        precondition(records.allSatisfy { $0.developerText == nil }, "production trace must not persist transcript bodies")

        for index in 0..<3 {
            let other = RealtimeTranscriptTrace(
                sessionID: UUID(),
                directoryURL: root,
                maximumRecordsPerSession: 3,
                maximumRetainedSessions: 2,
                developerTextSessionID: nil
            )
            other.recordMerge(
                result: result,
                transition: transition,
                confirmedCharacterCount: state.confirmedCharacterCount,
                volatileCharacterCount: state.mutableTailText.count
            )
            other.flushForTesting()
            if index == 2 {
                let files = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil
                ).filter { $0.pathExtension == "jsonl" }
                precondition(files.count == 2, "old trace sessions must be pruned")
            }
        }

        print("RealtimeTranscriptTraceCheck passed")
    }
}
