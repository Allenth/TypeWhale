import Foundation

struct PreviewAudioRange: Equatable, Codable, Sendable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }
}

enum PreviewSourceLane: String, Codable, Sendable {
    case fast
    case correction
    case stopTail
}

struct PreviewRecognitionResult: Equatable, Sendable {
    let sessionID: UUID
    let epoch: Int
    let requestID: UUID
    let chunkID: Int
    let sourceLane: PreviewSourceLane
    let audioRange: PreviewAudioRange
    let text: String
    let tokens: [String]
    let tokenTimestamps: [Float]?
    let boundary: PreviewBoundary?

    init(
        sessionID: UUID,
        epoch: Int,
        requestID: UUID,
        chunkID: Int,
        sourceLane: PreviewSourceLane,
        audioRange: PreviewAudioRange,
        text: String,
        tokens: [String],
        tokenTimestamps: [Float]?,
        boundary: PreviewBoundary? = nil
    ) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.requestID = requestID
        self.chunkID = chunkID
        self.sourceLane = sourceLane
        self.audioRange = audioRange
        self.text = text
        self.tokens = tokens
        self.tokenTimestamps = tokenTimestamps
        self.boundary = boundary
    }

    var validatedTokenTimestamps: [Float]? {
        guard let tokenTimestamps,
              tokenTimestamps.count == tokens.count,
              tokenTimestamps.allSatisfy({
                  $0.isFinite && $0 >= 0 && TimeInterval($0) <= audioRange.duration + 0.25
              }) else { return nil }
        for index in tokenTimestamps.indices.dropFirst() where tokenTimestamps[index] < tokenTimestamps[index - 1] {
            return nil
        }
        return tokenTimestamps
    }
}

struct PreviewTranscriptSegment: Equatable, Codable, Sendable {
    let id: UUID
    let text: String
    let audioRange: PreviewAudioRange
}

struct PreviewTranscriptState: Equatable, Sendable {
    var confirmedSegments: [PreviewTranscriptSegment]
    var mutableTailText: String
    var displayText: String
    var displayRevision: Int
    var recoveryRequested: Bool
    var confirmedCharacterCount: Int
    /// 展示快照：每次发布时与 displayText 同步产出；nil 表示该状态不是 Reducer 发布的（如降级兜底构造）。
    var displaySnapshot: PreviewDisplaySnapshot? = nil

    var confirmedText: String {
        confirmedSegments.map(\.text).joined()
    }
}

enum PreviewTranscriptEvent: Sendable {
    case fast(PreviewRecognitionResult)
    case correction(PreviewRecognitionResult)
}

enum PreviewOwnershipDecision: String, Codable, Sendable {
    case rejectedIdentity
    case ignoredStaleFast
    case fastStored
    case correctionPrimed
    case correctionRecovery
    case correctionMerged
}

struct PreviewOwnershipTransition: Equatable, Codable, Sendable {
    let decision: PreviewOwnershipDecision
    let replacementRange: PreviewAudioRange?
    let confirmedRange: PreviewAudioRange?
    let confirmedThroughTime: TimeInterval?
    let promotedFastCharacterCount: Int
    let promotedFastRange: PreviewAudioRange?
    let promotedFastText: String?
    let removedFastChunkIDs: [Int]
}
