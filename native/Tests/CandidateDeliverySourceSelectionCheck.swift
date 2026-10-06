import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

@main
struct CandidateDeliverySourceSelectionCheck {
    static func main() {
        prefersRealtimeDeliveryCacheOverShadowRuntime()
        ignoresShadowRuntimeWhenRealtimeDeliveryCacheIsMissing()
        print("CandidateDeliverySourceSelectionCheck passed")
    }

    private static func prefersRealtimeDeliveryCacheOverShadowRuntime() {
        let realRuntime = CandidateDeliverySnapshot(
            text: "真实旁路已经覆盖到最后一句。",
            source: .shadowRuntimeCache,
            lifecycle: .completed
        )
        let realtimeDelivery = CandidateDeliverySnapshot(
            text: "真实旁路已经覆盖",
            source: .realtimePreviewDeliveryCache,
            lifecycle: .completed
        )

        let selected = CandidateDeliverySnapshot.selectForFinalDelivery(
            shadowRuntimeSnapshot: realRuntime,
            realtimePreviewDeliverySnapshot: realtimeDelivery,
            languageMode: .chinese
        )

        precondition(selected == realtimeDelivery)
    }

    private static func ignoresShadowRuntimeWhenRealtimeDeliveryCacheIsMissing() {
        let realRuntime = CandidateDeliverySnapshot(
            text: "真实旁路已经完成，但不能作为最终粘贴权威。",
            source: .shadowRuntimeCache,
            lifecycle: .completed
        )

        let selected = CandidateDeliverySnapshot.selectForFinalDelivery(
            shadowRuntimeSnapshot: realRuntime,
            realtimePreviewDeliverySnapshot: nil,
            languageMode: .chinese
        )

        precondition(selected == nil)
    }
}
