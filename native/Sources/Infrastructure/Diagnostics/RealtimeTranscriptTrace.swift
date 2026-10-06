import CryptoKit
import Foundation

struct RealtimeTranscriptTraceRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case merge
        case finalCache
    }

    let schemaVersion: Int
    let sessionID: UUID
    let sequence: Int
    let timestamp: Date
    let kind: Kind
    let requestID: UUID?
    let lane: PreviewSourceLane?
    let chunkID: Int?
    let audioRange: PreviewAudioRange?
    let textCharacterCount: Int
    let textHash: String
    let confirmedCharacterCount: Int
    let volatileCharacterCount: Int
    let replacementRange: PreviewAudioRange?
    let confirmedRange: PreviewAudioRange?
    let decision: PreviewOwnershipDecision?
    let confirmedThroughTime: TimeInterval?
    let promotedFastCharacterCount: Int
    let promotedFastRange: PreviewAudioRange?
    let promotedFastTextHash: String?
    let removedFastChunkIDs: [Int]
    let developerText: String?
}

/// Privacy-safe ownership evidence for realtime transcript assembly.
/// All hashing and file IO run on a private serial queue; callers never wait for persistence.
final class RealtimeTranscriptTrace: @unchecked Sendable {
    private let sessionID: UUID
    private let directoryURL: URL
    private let fileURL: URL
    private let maximumRecordsPerSession: Int
    private let maximumRetainedSessions: Int
    private let includeDeveloperText: Bool
    private let hashSalt: Data
    private let queue: DispatchQueue
    private let encoder: JSONEncoder
    private var records: [RealtimeTranscriptTraceRecord] = []
    private var nextSequence = 1
    private var didPruneSessions = false

    init(
        sessionID: UUID,
        directoryURL: URL = RealtimeTranscriptTrace.defaultDirectoryURL(),
        maximumRecordsPerSession: Int = 512,
        maximumRetainedSessions: Int = 12,
        developerTextSessionID: UUID? = nil
    ) {
        self.sessionID = sessionID
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("\(sessionID.uuidString).jsonl")
        self.maximumRecordsPerSession = max(1, maximumRecordsPerSession)
        self.maximumRetainedSessions = max(1, maximumRetainedSessions)
        self.includeDeveloperText = developerTextSessionID == sessionID
        self.hashSalt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        self.queue = DispatchQueue(
            label: "com.waykingah.typewhale.realtime-transcript-trace.\(sessionID.uuidString)"
        )
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func recordMerge(
        result: PreviewRecognitionResult,
        transition: PreviewOwnershipTransition,
        confirmedCharacterCount: Int,
        volatileCharacterCount: Int
    ) {
        let requestID = result.requestID
        let lane = result.sourceLane
        let chunkID = result.chunkID
        let audioRange = result.audioRange
        let text = result.text
        queue.async { [self] in
            appendRecord(
                kind: .merge,
                requestID: requestID,
                lane: lane,
                chunkID: chunkID,
                audioRange: audioRange,
                text: text,
                confirmedCharacterCount: confirmedCharacterCount,
                volatileCharacterCount: volatileCharacterCount,
                transition: transition
            )
        }
    }

    func recordFinalCache(text: String) {
        queue.async { [self] in
            appendRecord(
                kind: .finalCache,
                requestID: nil,
                lane: nil,
                chunkID: nil,
                audioRange: nil,
                text: text,
                confirmedCharacterCount: text.count,
                volatileCharacterCount: 0,
                transition: nil
            )
        }
    }

    func flushForTesting() {
        queue.sync {}
    }

    func readRecordsForTesting() throws -> [RealtimeTranscriptTraceRecord] {
        try Self.decodeRecords(at: fileURL, decoder: JSONDecoder())
    }

    private func appendRecord(
        kind: RealtimeTranscriptTraceRecord.Kind,
        requestID: UUID?,
        lane: PreviewSourceLane?,
        chunkID: Int?,
        audioRange: PreviewAudioRange?,
        text: String,
        confirmedCharacterCount: Int,
        volatileCharacterCount: Int,
        transition: PreviewOwnershipTransition?
    ) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let record = RealtimeTranscriptTraceRecord(
                schemaVersion: 1,
                sessionID: sessionID,
                sequence: nextSequence,
                timestamp: Date(),
                kind: kind,
                requestID: requestID,
                lane: lane,
                chunkID: chunkID,
                audioRange: audioRange,
                textCharacterCount: text.count,
                textHash: hash(text),
                confirmedCharacterCount: confirmedCharacterCount,
                volatileCharacterCount: volatileCharacterCount,
                replacementRange: transition?.replacementRange,
                confirmedRange: transition?.confirmedRange,
                decision: transition?.decision,
                confirmedThroughTime: transition?.confirmedThroughTime,
                promotedFastCharacterCount: transition?.promotedFastCharacterCount ?? 0,
                promotedFastRange: transition?.promotedFastRange,
                promotedFastTextHash: transition?.promotedFastText.map(hash),
                removedFastChunkIDs: transition?.removedFastChunkIDs ?? [],
                developerText: includeDeveloperText ? text : nil
            )
            nextSequence += 1
            records.append(record)
            if records.count > maximumRecordsPerSession {
                let retainedCount = max(1, maximumRecordsPerSession / 2)
                records.removeFirst(records.count - retainedCount)
                try persistRecords()
            } else {
                try append(record)
            }
            if !didPruneSessions {
                try pruneOldSessions()
                didPruneSessions = true
            }
        } catch {
            LaunchDiagnostics.markAsync(
                "realtime_transcript_trace_write_failed session_id=\(sessionID.uuidString.prefix(8)) error=\(error.localizedDescription)"
            )
        }
    }

    private func persistRecords() throws {
        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func append(_ record: RealtimeTranscriptTraceRecord) throws {
        var data = try encoder.encode(record)
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func pruneOldSessions() throws {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }
        guard files.count > maximumRetainedSessions else { return }
        let sorted = try files.sorted { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: keys).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: keys).contentModificationDate ?? .distantPast
            if lhsDate == rhsDate { return lhs.lastPathComponent < rhs.lastPathComponent }
            return lhsDate < rhsDate
        }
        for obsolete in sorted.prefix(files.count - maximumRetainedSessions) {
            try FileManager.default.removeItem(at: obsolete)
        }
    }

    private func hash(_ text: String) -> String {
        var data = hashSalt
        data.append(contentsOf: text.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDirectoryURL() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("TypeWhale Pro", isDirectory: true)
            .appendingPathComponent("RealtimeTranscriptTrace", isDirectory: true)
    }

    private static func decodeRecords(
        at url: URL,
        decoder: JSONDecoder
    ) throws -> [RealtimeTranscriptTraceRecord] {
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map { line in
            try decoder.decode(RealtimeTranscriptTraceRecord.self, from: Data(line))
        }
    }
}
