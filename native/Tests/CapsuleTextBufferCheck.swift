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

        _ = buffer.setTarget("今天我们先检查实时预览继续")
        precondition(buffer.targetDraft == "今天我们先检查实时预览继续")
        precondition(buffer.displayedDraft == firstTarget)

        let replacementTarget = "静音之后不要把新旧文本按位搅在一起"
        let replacement = buffer.setTarget(replacementTarget)
        guard case .updated(let fadeStartIndex?, let needsDraftTimer, let shouldStopDraftTimer) = replacement else {
            preconditionFailure("Expected replacement update")
        }
        let expectedCatchUpCount = max(firstTarget.count, replacementTarget.count - 4)
        precondition(fadeStartIndex == expectedCatchUpCount)
        precondition(needsDraftTimer)
        precondition(!shouldStopDraftTimer)
        assert(buffer.displayedDraft, equals: String(replacementTarget.prefix(expectedCatchUpCount)))
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

        let catchUpBuffer = CapsuleTextBuffer(animatedTailLimit: 4, firstPreviewMinimumCharacters: 2)
        _ = catchUpBuffer.setTarget("短句开始")
        while catchUpBuffer.displayedDraft != catchUpBuffer.targetDraft {
            _ = catchUpBuffer.advance()
        }
        _ = catchUpBuffer.setTarget("短句开始之后突然收到一大段校正文本需要立刻追上实时说话位置")
        precondition(
            catchUpBuffer.targetDraft.count - catchUpBuffer.displayedDraft.count <= 4,
            "every update must bound the animated backlog, not only the first preview"
        )
        var catchUpAdvanceCount = 0
        while catchUpBuffer.displayedDraft != catchUpBuffer.targetDraft {
            _ = catchUpBuffer.advance()
            catchUpAdvanceCount += 1
        }
        precondition(catchUpAdvanceCount == 4, "the bounded tail should finish in exactly the configured number of steps")

        let continuousBuffer = CapsuleTextBuffer(animatedTailLimit: 4, firstPreviewMinimumCharacters: 2)
        let continuousTargets = [
            "我们开始测试连续预览",
            "我们开始测试连续预览是否能稳定跟上",
            "我们开始测试连续预览是否能稳定跟上语速并保持丝滑",
            "我们开始测试连续预览是否能稳定跟上语速并保持丝滑不会越来越慢"
        ]
        for target in continuousTargets {
            _ = continuousBuffer.setTarget(target)
            precondition(
                continuousBuffer.targetDraft.count - continuousBuffer.displayedDraft.count <= 4,
                "repeated realtime updates must never accumulate more than one animated tail"
            )
            for _ in 0..<6 {
                _ = continuousBuffer.advance()
            }
        }
        assert(continuousBuffer.displayedDraft, equals: continuousTargets.last!)
    }

    private static func assert(_ actual: String, equals expected: String) {
        precondition(actual == expected, "Expected [\(expected)], got [\(actual)]")
    }
}
