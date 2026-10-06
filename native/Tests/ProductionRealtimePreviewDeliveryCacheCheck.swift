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
struct ProductionRealtimePreviewDeliveryCacheCheck {
    static func main() {
        resetStartsEmpty()
        completedSnapshotKeepsProductionPreviewContent()
        completionObserverReceivesExactDeliverySnapshot()
        incompleteTailStillReturnsAvailableText()
        print("ProductionRealtimePreviewDeliveryCacheCheck passed")
    }

    private static func completionObserverReceivesExactDeliverySnapshot() {
        final class Box: @unchecked Sendable {
            var snapshot: CompleteTranscriptSnapshot?
        }
        let box = Box()
        var cache = ProductionRealtimePreviewDeliveryCache()
        cache.reset(completionObserver: { snapshot in
            box.snapshot = snapshot
        })
        cache.consume(CompleteTranscriptSnapshot(
            revision: 9,
            stableText: "完整缓存",
            volatileTailText: "最终尾巴",
            lifecycle: .running,
            sourceIdentity: "test-production"
        ))
        cache.complete()

        precondition(box.snapshot?.deliveryText == cache.deliverySnapshot()?.text)
        precondition(box.snapshot?.lifecycle == .completed)
    }

    private static func resetStartsEmpty() {
        var cache = ProductionRealtimePreviewDeliveryCache()
        cache.consume(CompleteTranscriptSnapshot(
            revision: 1,
            stableText: "用户体验",
            volatileTailText: "不要了吗",
            lifecycle: .running,
            sourceIdentity: "test-production"
        ))
        cache.reset()

        precondition(cache.deliverySnapshot() == nil)
    }

    private static func completedSnapshotKeepsProductionPreviewContent() {
        var cache = ProductionRealtimePreviewDeliveryCache()
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

    private static func incompleteTailStillReturnsAvailableText() {
        var cache = ProductionRealtimePreviewDeliveryCache()
        cache.consume(
            CompleteTranscriptSnapshot(
                revision: 12,
                stableText: "停顿后继续",
                volatileTailText: "说话",
                lifecycle: .running,
                sourceIdentity: "test-production"
            ),
            audioCoverageSeconds: 27.4
        )
        cache.complete(recordingDurationSeconds: 28.0)

        let snapshot = cache.deliverySnapshot()
        precondition(snapshot?.text == "停顿后继续说话")
        precondition(snapshot?.source == .realtimePreviewDeliveryCache)
        precondition(snapshot?.lifecycle == .completed)
    }
}
