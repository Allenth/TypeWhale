import Foundation

@main
struct IncrementalTranscriptStoreCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = UUID()
        let store = IncrementalTranscriptStore(rootDirectory: root)
        try store.begin(sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 100))

        let first = PreviewTranscriptSegment(id: UUID(), text: "第一段。", audioRange: .init(start: 0, end: 10))
        let second = PreviewTranscriptSegment(id: UUID(), text: "第二段。", audioRange: .init(start: 10, end: 20))
        try store.appendConfirmed(first, sessionID: sessionID)
        try store.appendConfirmed(second, sessionID: sessionID)
        try store.appendConfirmed(second, sessionID: sessionID)
        let replayed = try store.replayConfirmed(sessionID: sessionID)
        precondition(replayed == [first, second], "retries must be idempotent")

        let eventsURL = root.appendingPathComponent(sessionID.uuidString).appendingPathComponent("segments.jsonl")
        let partial = try FileHandle(forWritingTo: eventsURL)
        try partial.seekToEnd()
        try partial.write(contentsOf: Data("{\"partial\":".utf8))
        try partial.close()
        let replayedAfterPartial = try store.replayConfirmed(sessionID: sessionID)
        precondition(replayedAfterPartial == [first, second], "truncated final JSONL record must be ignored")

        let final = try store.finalize(
            sessionID: sessionID,
            authoritativeConfirmedText: "第一段。第二段。",
            tail: "结尾。",
            degraded: false
        )
        precondition(final == "第一段。第二段。结尾。")
        precondition(FileManager.default.fileExists(atPath: store.finalTranscriptURL(sessionID: sessionID).path))

        let memoryOnlyID = UUID()
        try store.begin(sessionID: memoryOnlyID, startedAt: Date())
        let memoryFinal = try store.finalize(
            sessionID: memoryOnlyID,
            authoritativeConfirmedText: "内存权威段。",
            tail: "尾部。",
            degraded: true
        )
        precondition(memoryFinal == "内存权威段。尾部。")

        print("IncrementalTranscriptStoreCheck passed")
    }
}
