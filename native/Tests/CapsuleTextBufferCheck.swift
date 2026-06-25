import Foundation

@main
struct CapsuleTextBufferCheck {
    static func main() {
        let buffer = CapsuleTextBuffer(animatedTailLimit: 4, firstPreviewMinimumCharacters: 2)

        let firstTarget = "今天我们先检查实时预览"
        let firstUpdate = buffer.setTarget(firstTarget)
        guard case .updated(let firstFadeStartIndex?, let firstNeedsDraftTimer, let firstShouldStopDraftTimer) = firstUpdate else {
            preconditionFailure("Expected first update")
        }
        precondition(firstFadeStartIndex == 0)
        precondition(firstNeedsDraftTimer)
        precondition(!firstShouldStopDraftTimer)
        while buffer.displayedDraft != buffer.targetDraft {
            _ = buffer.advance()
        }
        assert(buffer.displayedDraft, equals: firstTarget)

        _ = buffer.setTarget("今天我们先检查实时预览，然后修复静音后的跳字")
        precondition(buffer.targetDraft == "今天我们先检查实时预览，然后修复静音后的跳字")
        precondition(buffer.displayedDraft == firstTarget)

        let replacementTarget = "静音之后不要把新旧文本按位搅在一起"
        let replacement = buffer.setTarget(replacementTarget)
        guard case .updated(let fadeStartIndex?, let needsDraftTimer, let shouldStopDraftTimer) = replacement else {
            preconditionFailure("Expected replacement update")
        }
        precondition(fadeStartIndex == firstTarget.count)
        precondition(needsDraftTimer)
        precondition(!shouldStopDraftTimer)
        assert(buffer.displayedDraft, equals: String(replacementTarget.prefix(firstTarget.count)))
        assert(buffer.targetDraft, equals: replacementTarget)
        while buffer.displayedDraft != buffer.targetDraft {
            _ = buffer.advance()
        }
        assert(buffer.displayedDraft, equals: replacementTarget)

        let shorterTarget = "静音之后不要乱跳"
        let shorterReplacement = buffer.setTarget(shorterTarget)
        guard case .updated(let shorterFadeStartIndex, let shorterNeedsDraftTimer, let shorterShouldStopDraftTimer) = shorterReplacement else {
            preconditionFailure("Expected shorter replacement update")
        }
        precondition(shorterFadeStartIndex == nil)
        precondition(!shorterNeedsDraftTimer)
        precondition(shorterShouldStopDraftTimer)
        let expectedRefreshed = shorterTarget + String(replacementTarget.dropFirst(shorterTarget.count))
        assert(buffer.displayedDraft, equals: expectedRefreshed)
        assert(buffer.targetDraft, equals: expectedRefreshed)
    }

    private static func assert(_ actual: String, equals expected: String) {
        precondition(actual == expected, "Expected [\(expected)], got [\(actual)]")
    }
}
