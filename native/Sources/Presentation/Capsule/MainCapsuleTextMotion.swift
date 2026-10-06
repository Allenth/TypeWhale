import Foundation

enum MainCapsuleTextMotionUpdate: Equatable {
    case unchanged
    case updated(needsTimer: Bool)
}

enum MainCapsuleTextMotionAdvance: Equatable {
    case advanced
    case finished
}

struct MainCapsuleTextMotion {
    private static let maximumAnimatedBacklog = 12

    private(set) var visibleCharacterCount = 0
    private(set) var targetCharacterCount = 0
    private(set) var stableTargetCharacterCount = 0

    init() {}

    init(
        visibleCharacterCount: Int,
        targetCharacterCount: Int,
        stableCharacterCount: Int
    ) {
        let target = max(0, targetCharacterCount)
        self.targetCharacterCount = target
        self.visibleCharacterCount = min(max(0, visibleCharacterCount), target)
        self.stableTargetCharacterCount = min(max(0, stableCharacterCount), target)
    }

    var visibleStableCharacterCount: Int {
        min(stableTargetCharacterCount, visibleCharacterCount)
    }

    var needsTimer: Bool {
        visibleCharacterCount < targetCharacterCount
    }

    mutating func apply(
        targetCharacterCount: Int,
        stableCharacterCount: Int
    ) -> MainCapsuleTextMotionUpdate {
        let nextTargetCount = max(0, targetCharacterCount)
        let nextStableCount = max(0, min(stableCharacterCount, nextTargetCount))
        guard nextTargetCount != self.targetCharacterCount
                || nextStableCount != self.stableTargetCharacterCount else {
            return .unchanged
        }

        let previousTargetCount = self.targetCharacterCount
        self.targetCharacterCount = nextTargetCount
        self.stableTargetCharacterCount = nextStableCount

        if nextTargetCount == 0 {
            visibleCharacterCount = 0
        } else if previousTargetCount == 0 {
            visibleCharacterCount = max(1, nextTargetCount - Self.maximumAnimatedBacklog)
        } else if visibleCharacterCount > nextTargetCount {
            visibleCharacterCount = nextTargetCount
        } else if nextTargetCount - visibleCharacterCount > Self.maximumAnimatedBacklog {
            visibleCharacterCount = nextTargetCount - Self.maximumAnimatedBacklog
        }

        return .updated(needsTimer: needsTimer)
    }

    mutating func advance() -> MainCapsuleTextMotionAdvance {
        guard visibleCharacterCount < targetCharacterCount else {
            return .finished
        }

        visibleCharacterCount += 1
        return visibleCharacterCount < targetCharacterCount ? .advanced : .finished
    }

    mutating func reset() {
        visibleCharacterCount = 0
        targetCharacterCount = 0
        stableTargetCharacterCount = 0
    }
}
