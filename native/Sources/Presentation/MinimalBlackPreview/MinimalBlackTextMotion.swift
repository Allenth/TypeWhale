import Foundation

enum MinimalBlackTextMotionUpdate: Equatable, Sendable {
    case unchanged
    case updated(needsTimer: Bool)
}

enum MinimalBlackTextMotionAdvance: Equatable, Sendable {
    case advanced
    case finished
}

struct MinimalBlackTextMotion: Sendable {
    private static let maximumAnimatedBacklog = 12

    private(set) var visibleCharacterCount = 0
    private(set) var targetCharacterCount = 0

    var needsTimer: Bool { visibleCharacterCount < targetCharacterCount }

    mutating func apply(contentCharacterCount: Int) -> MinimalBlackTextMotionUpdate {
        let nextCount = max(0, contentCharacterCount)
        guard nextCount != targetCharacterCount else { return .unchanged }

        let previousTarget = targetCharacterCount
        targetCharacterCount = nextCount
        if nextCount == 0 {
            visibleCharacterCount = 0
        } else if previousTarget == 0 {
            visibleCharacterCount = max(1, nextCount - Self.maximumAnimatedBacklog)
        } else if visibleCharacterCount > nextCount {
            visibleCharacterCount = nextCount
        } else if nextCount - visibleCharacterCount > Self.maximumAnimatedBacklog {
            visibleCharacterCount = nextCount - Self.maximumAnimatedBacklog
        }
        return .updated(needsTimer: needsTimer)
    }

    mutating func advance() -> MinimalBlackTextMotionAdvance {
        guard visibleCharacterCount < targetCharacterCount else { return .finished }
        visibleCharacterCount += 1
        return visibleCharacterCount < targetCharacterCount ? .advanced : .finished
    }

    mutating func reset() {
        visibleCharacterCount = 0
        targetCharacterCount = 0
    }
}
