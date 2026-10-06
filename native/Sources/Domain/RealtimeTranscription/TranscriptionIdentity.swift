import Foundation

struct TranscriptionSessionID: Hashable, Sendable {
    let rawValue: UUID
}

struct TranscriptionAudioRange: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }
}

struct TranscriptSegment: Equatable, Sendable {
    let id: String
    let text: String
    let audioRange: TranscriptionAudioRange
}
