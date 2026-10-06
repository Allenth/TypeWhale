import Foundation

@main
struct PasteboardReadinessGateCheck {
    static func main() {
        let expectedText = "本轮应该粘贴的新内容"

        assertDecision(
            snapshot: PasteboardReadinessGate.Snapshot(
                expectedText: expectedText,
                injectedChangeCount: 42,
                currentChangeCount: 42,
                currentString: expectedText
            ),
            expected: .ready,
            message: "matching pasteboard text should be ready immediately"
        )

        assertDecision(
            snapshot: PasteboardReadinessGate.Snapshot(
                expectedText: expectedText,
                injectedChangeCount: 42,
                currentChangeCount: 42,
                currentString: nil
            ),
            expected: .retry,
            message: "same change count without readable text should retry instead of pasting stale clipboard"
        )

        assertDecision(
            snapshot: PasteboardReadinessGate.Snapshot(
                expectedText: expectedText,
                injectedChangeCount: 42,
                currentChangeCount: 43,
                currentString: "上一轮旧内容"
            ),
            expected: .stolen,
            message: "changed pasteboard with different text must be treated as stolen"
        )

        assertDecision(
            snapshot: PasteboardReadinessGate.Snapshot(
                expectedText: expectedText,
                injectedChangeCount: 42,
                currentChangeCount: 43,
                currentString: expectedText
            ),
            expected: .ready,
            message: "matching text is safe even if the pasteboard change count advanced"
        )

        print("PasteboardReadinessGateCheck passed")
    }

    private static func assertDecision(
        snapshot: PasteboardReadinessGate.Snapshot,
        expected: PasteboardReadinessGate.Decision,
        message: String
    ) {
        let actual = PasteboardReadinessGate.evaluate(snapshot)
        precondition(actual == expected, "\(message): expected \(expected), got \(actual)")
    }
}
