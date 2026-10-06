import Foundation

@main
struct MainCapsuleTextMotionCheck {
    static func main() {
        growsTargetWithoutJumpingVisibleProgress()
        advancesVisibleProgressOneCharacterAtATime()
        keepsAnimatedBacklogSmall()
        clampsStableAndVisibleCountsWhenTextShrinks()
        bridgesExistingVisibleCountsWithoutAnimatingAgain()
        resetClearsMotionState()
        print("MainCapsuleTextMotionCheck passed")
    }

    private static func growsTargetWithoutJumpingVisibleProgress() {
        var motion = MainCapsuleTextMotion()
        let first = motion.apply(targetCharacterCount: 3, stableCharacterCount: 1)
        precondition(first == .updated(needsTimer: true))
        precondition(motion.targetCharacterCount == 3)
        precondition(motion.visibleCharacterCount == 1)
        precondition(motion.stableTargetCharacterCount == 1)
        precondition(motion.visibleStableCharacterCount == 1)

        _ = motion.advance()
        let growth = motion.apply(targetCharacterCount: 5, stableCharacterCount: 3)
        precondition(growth == .updated(needsTimer: true))
        precondition(motion.targetCharacterCount == 5)
        precondition(motion.visibleCharacterCount == 2)
        precondition(motion.stableTargetCharacterCount == 3)
        precondition(motion.visibleStableCharacterCount == 2)
    }

    private static func advancesVisibleProgressOneCharacterAtATime() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 4, stableCharacterCount: 4)

        precondition(motion.advance() == .advanced)
        precondition(motion.visibleCharacterCount == 2)
        precondition(motion.advance() == .advanced)
        precondition(motion.visibleCharacterCount == 3)
        precondition(motion.advance() == .finished)
        precondition(motion.visibleCharacterCount == 4)
        precondition(motion.advance() == .finished)
        precondition(motion.visibleCharacterCount == 4)
    }

    private static func keepsAnimatedBacklogSmall() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 30, stableCharacterCount: 20)

        precondition(motion.targetCharacterCount == 30)
        precondition(motion.visibleCharacterCount == 18)
        precondition(motion.visibleStableCharacterCount == 18)
        precondition(motion.needsTimer)
    }

    private static func clampsStableAndVisibleCountsWhenTextShrinks() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 8, stableCharacterCount: 6)
        while motion.needsTimer {
            _ = motion.advance()
        }

        let shrink = motion.apply(targetCharacterCount: 2, stableCharacterCount: 4)
        precondition(shrink == .updated(needsTimer: false))
        precondition(motion.targetCharacterCount == 2)
        precondition(motion.visibleCharacterCount == 2)
        precondition(motion.stableTargetCharacterCount == 2)
        precondition(motion.visibleStableCharacterCount == 2)
    }

    private static func bridgesExistingVisibleCountsWithoutAnimatingAgain() {
        let motion = MainCapsuleTextMotion(
            visibleCharacterCount: 4,
            targetCharacterCount: 6,
            stableCharacterCount: 3
        )

        precondition(motion.visibleCharacterCount == 4)
        precondition(motion.targetCharacterCount == 6)
        precondition(motion.stableTargetCharacterCount == 3)
        precondition(motion.visibleStableCharacterCount == 3)
        precondition(motion.needsTimer)

        let clamped = MainCapsuleTextMotion(
            visibleCharacterCount: 10,
            targetCharacterCount: 2,
            stableCharacterCount: 8
        )

        precondition(clamped.visibleCharacterCount == 2)
        precondition(clamped.targetCharacterCount == 2)
        precondition(clamped.stableTargetCharacterCount == 2)
        precondition(clamped.visibleStableCharacterCount == 2)
        precondition(clamped.needsTimer == false)
    }

    private static func resetClearsMotionState() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 6, stableCharacterCount: 3)
        motion.reset()

        precondition(motion.targetCharacterCount == 0)
        precondition(motion.visibleCharacterCount == 0)
        precondition(motion.stableTargetCharacterCount == 0)
        precondition(motion.visibleStableCharacterCount == 0)
        precondition(motion.needsTimer == false)
    }
}
