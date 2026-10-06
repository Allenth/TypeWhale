import Foundation

enum MiMoRequestPartialUpdate: Equatable, Sendable {
    case suppressedReplay
    case emit(String)
}

struct MiMoRequestPartialProjection: Sendable {
    private var snapshotID: String?
    private var baselineText = ""
    private var lastEmittedText: String?

    mutating func begin(snapshotID: String, baselineText: String) {
        self.snapshotID = snapshotID
        self.baselineText = baselineText
        lastEmittedText = nil
    }

    mutating func accept(
        snapshotID: String,
        incomingText: String
    ) -> MiMoRequestPartialUpdate {
        guard self.snapshotID == snapshotID else { return .suppressedReplay }
        guard !baselineText.hasPrefix(incomingText) else { return .suppressedReplay }
        guard incomingText.count >= baselineText.count else { return .suppressedReplay }
        guard lastEmittedText != incomingText else { return .suppressedReplay }
        lastEmittedText = incomingText
        return .emit(incomingText)
    }

    mutating func end(snapshotID: String) {
        guard self.snapshotID == snapshotID else { return }
        reset()
    }

    mutating func reset() {
        snapshotID = nil
        baselineText = ""
        lastEmittedText = nil
    }
}
