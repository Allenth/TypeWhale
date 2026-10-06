import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

@main
struct CandidateTranscriptQualityGateCheck {
    static func main() {
        let gate = CandidateTranscriptQualityGate()

        let repeated = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "案用户体验验不要了吗？？？",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "怎么可能有这样的方案呢？用户体验不要了吗？",
            languageMode: .chinese
        )
        precondition(repeated.decision != .accept)

        let duplicatedDesign = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "代码设计计排查一下。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "代码设计排查一下。",
            languageMode: .chinese
        )
        precondition(duplicatedDesign.decision == .reject(.repeatedShortUnit))

        let orphan = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "了用户体验不要了吗？？",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "怎么可能用这样的方案呢？用户体验不要了吗？",
            languageMode: .chinese
        )
        precondition(orphan.decision != .accept)

        let clean = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "今天我们讨论功能优化",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "今天我们讨论功能优化",
            languageMode: .chinese
        )
        precondition(clean.decision == .accept)
        precondition(clean.normalizedCandidateText == "今天我们讨论功能优化")

        let naturalRepeat = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "我们好好看看这个问题。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "我们好好看看这个问题。",
            languageMode: .chinese
        )
        precondition(naturalRepeat.decision == .accept)

        let longerThanPreview = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "今天我们讨论功能优化这样的一个情况，如果可以的话我们继续推进。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            realtimePreviewFallbackText: "今天我们讨论功能优化",
            languageMode: .chinese
        )
        precondition(longerThanPreview.decision == .accept)

        let running = gate.evaluate(
            candidate: CandidateDeliverySnapshot(
                text: "还没有完成",
                source: .shadowRuntimeCache,
                lifecycle: .running
            ),
            realtimePreviewFallbackText: "还没有完成",
            languageMode: .chinese
        )
        precondition(running.decision == .reject(.notCompleted))

        print("CandidateTranscriptQualityGateCheck passed")
    }
}
