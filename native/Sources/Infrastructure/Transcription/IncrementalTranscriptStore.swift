import Foundation

final class IncrementalTranscriptStore: @unchecked Sendable {
    private struct Metadata: Codable {
        let sessionID: UUID
        let startedAt: Date
        var finalizedAt: Date?
        var degraded: Bool
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var writtenSegmentIDs: [UUID: Set<UUID>] = [:]

    init(
        rootDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhale Pro/TranscriptionSessions", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func begin(sessionID: UUID, startedAt: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        let directory = sessionDirectory(sessionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let metadata = Metadata(sessionID: sessionID, startedAt: startedAt, finalizedAt: nil, degraded: false)
        try encoder.encode(metadata).write(to: metadataURL(sessionID), options: .atomic)
        writtenSegmentIDs[sessionID] = []
        if !fileManager.fileExists(atPath: eventsURL(sessionID).path) {
            fileManager.createFile(atPath: eventsURL(sessionID).path, contents: nil)
        }
    }

    func appendConfirmed(_ segment: PreviewTranscriptSegment, sessionID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if writtenSegmentIDs[sessionID, default: []].contains(segment.id) { return }
        var data = try encoder.encode(segment)
        data.append(0x0A)
        let url = eventsURL(sessionID)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        writtenSegmentIDs[sessionID, default: []].insert(segment.id)
    }

    func replayConfirmed(sessionID: UUID) throws -> [PreviewTranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: eventsURL(sessionID).path) else { return [] }
        let data = try Data(contentsOf: eventsURL(sessionID))
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var segments: [PreviewTranscriptSegment] = []
        for (index, line) in lines.enumerated() {
            do {
                segments.append(try decoder.decode(PreviewTranscriptSegment.self, from: Data(line)))
            } catch where index == lines.count - 1 {
                break
            }
        }
        return segments
    }

    func finalize(
        sessionID: UUID,
        authoritativeConfirmedText: String,
        tail: String,
        degraded: Bool
    ) throws -> String {
        let final = authoritativeConfirmedText + tail
        lock.lock()
        defer { lock.unlock() }
        try Data(final.utf8).write(to: finalTranscriptURL(sessionID: sessionID), options: .atomic)
        if let metadataData = try? Data(contentsOf: metadataURL(sessionID)),
           var metadata = try? decoder.decode(Metadata.self, from: metadataData) {
            metadata.finalizedAt = Date()
            metadata.degraded = degraded
            try encoder.encode(metadata).write(to: metadataURL(sessionID), options: .atomic)
        }
        return final
    }

    func finalTranscriptURL(sessionID: UUID) -> URL {
        sessionDirectory(sessionID).appendingPathComponent("transcript.txt")
    }

    private func sessionDirectory(_ sessionID: UUID) -> URL {
        rootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func metadataURL(_ sessionID: UUID) -> URL {
        sessionDirectory(sessionID).appendingPathComponent("session.json")
    }

    private func eventsURL(_ sessionID: UUID) -> URL {
        sessionDirectory(sessionID).appendingPathComponent("segments.jsonl")
    }
}
