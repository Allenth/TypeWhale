import Foundation

@main
struct MinimalBlackPresentationCheck {
    static func main() {
        animationBacklogStaysBounded()
        stableAndVolatileTextRemainSeparate()
        shrinkingContentNeverShowsRemovedCharacters()
        print("MinimalBlackPresentationCheck passed")
    }

    private static func animationBacklogStaysBounded() {
        var motion = MinimalBlackTextMotion()
        precondition(motion.apply(contentCharacterCount: 40) == .updated(needsTimer: true))
        precondition(motion.targetCharacterCount - motion.visibleCharacterCount == 12)
        while motion.advance() != .finished {}
        precondition(motion.visibleCharacterCount == 40)
    }

    private static func stableAndVolatileTextRemainSeparate() {
        var state = MinimalBlackRenderState.empty
        state.apply(stableWindowText: "已确认", volatileTailText: "尾巴")
        precondition(state.displayText == "已确认尾巴")
        precondition(state.stableCharacterCount == 3)
    }

    private static func shrinkingContentNeverShowsRemovedCharacters() {
        var motion = MinimalBlackTextMotion()
        _ = motion.apply(contentCharacterCount: 20)
        while motion.advance() != .finished {}
        precondition(motion.apply(contentCharacterCount: 4) == .updated(needsTimer: false))
        precondition(motion.visibleCharacterCount == 4)
        precondition(motion.targetCharacterCount == 4)
    }
}
