import Foundation

enum TranscriptionLifecycle: Equatable, Sendable {
    case running
    case completed
}

enum CandidateDeliverySnapshotSource: String, Sendable {
    case legacyCandidateAdapter = "legacy-candidate-adapter"
    case realtimePreviewDeliveryCache = "realtime-preview-delivery-cache"
}

struct CandidateDeliverySnapshot: Equatable, Sendable {
    let text: String
    let source: CandidateDeliverySnapshotSource
    let lifecycle: TranscriptionLifecycle
}

@main
struct RealtimePreviewDeliveryCacheCheck {
    static func main() {
        deliversRealtimePreviewContent()
        completedSnapshotKeepsRealtimePreviewContent()
        completeTranscriptIsNotTruncatedToVisibleTail()
        print("RealtimePreviewDeliveryCacheCheck passed")
    }

    private static func deliversRealtimePreviewContent() {
        var cache = RealtimePreviewDeliveryCache()
        cache.consume(CompleteTranscriptSnapshot(
            revision: 7,
            stableText: "用户体验",
            volatileTailText: "不要了吗",
            lifecycle: .running,
            sourceIdentity: "test-production"
        ))

        let snapshot = cache.deliverySnapshot()
        precondition(snapshot?.text == "用户体验不要了吗")
        precondition(snapshot?.source == .realtimePreviewDeliveryCache)
        precondition(snapshot?.lifecycle == .running)
    }

    private static func completedSnapshotKeepsRealtimePreviewContent() {
        var cache = RealtimePreviewDeliveryCache()
        cache.consume(CompleteTranscriptSnapshot(
            revision: 8,
            stableText: "代码设计",
            volatileTailText: "排查一下",
            lifecycle: .running,
            sourceIdentity: "test-production"
        ))
        cache.complete()

        let snapshot = cache.deliverySnapshot()
        precondition(snapshot?.text == "代码设计排查一下")
        precondition(snapshot?.source == .realtimePreviewDeliveryCache)
        precondition(snapshot?.lifecycle == .completed)
    }

    private static func completeTranscriptIsNotTruncatedToVisibleTail() {
        let fullText = String(repeating: "完整转录", count: 125)
        precondition(fullText.count == 500)
        let visibleTail = String(fullText.suffix(160))
        precondition(visibleTail.count == 160)

        var cache = RealtimePreviewDeliveryCache()
        cache.consume(CompleteTranscriptSnapshot(
            revision: 9,
            stableText: fullText,
            volatileTailText: "",
            lifecycle: .running,
            sourceIdentity: "test-production"
        ))
        cache.complete()

        precondition(cache.deliverySnapshot()?.text == fullText)
        precondition(cache.deliverySnapshot()?.text != visibleTail)
    }
}
