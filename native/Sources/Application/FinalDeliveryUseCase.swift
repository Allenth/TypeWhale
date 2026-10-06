import Foundation

/// 最终交付结果：明确的文本、来源引擎标识和可读原因，供协调器直接消费。
/// UI 不参与本选择；Provider 不知道粘贴策略。
struct FinalDeliveryOutcome {
    let text: String
    let source: String
    let reason: String
    let recognitionSeconds: Double
}

/// SenseVoice 可使用完整实时缓存；其他已选后端必须执行完整 Final ASR。
/// shadow runtime 只保留为展示/诊断/迁移对照，UI 可见文本没有交付权威，
/// 已选非 SenseVoice 后端失败时也不能成为兜底来源。
struct FinalDeliveryUseCase {
    let recognitionUseCase: FinalRecognitionUseCase

    func deliver(
        taskID: UUID,
        audioURL: URL,
        configuration: ASRConfiguration,
        audioDuration: TimeInterval,
        shadowRuntimeSnapshot: CandidateDeliverySnapshot?,
        realtimePreviewDeliverySnapshot: CandidateDeliverySnapshot?,
        reRecognizeWholeRecordingAfterStop: Bool,
        completion: @escaping (FinalDeliveryOutcome) -> Void
    ) {
        let candidateSnapshot = realtimePreviewDeliverySnapshot
        let shadowQuality = CandidateTranscriptQualityGate().evaluate(
            candidate: shadowRuntimeSnapshot,
            realtimePreviewFallbackText: "",
            languageMode: configuration.languageMode
        )
        let candidateQuality = CandidateTranscriptQualityGate().evaluate(
            candidate: candidateSnapshot,
            realtimePreviewFallbackText: "",
            languageMode: configuration.languageMode
        )
        let candidateText = candidateSnapshot.map {
            cleanRecognitionText($0.text, languageMode: configuration.languageMode)
        } ?? ""
        let candidateEngine: String
        if let candidateSnapshot {
            candidateEngine = candidateSnapshot.lifecycle == .completed
                ? candidateSnapshot.source.rawValue
                : "\(candidateSnapshot.source.rawValue)-partial"
        } else {
            candidateEngine = "realtime-preview-cache-unavailable"
        }

        let request = FinalRecognitionRequest(
            taskID: taskID,
            audioURL: audioURL,
            configuration: configuration,
            audioDuration: audioDuration,
            completeRealtimeCacheText: candidateText,
            completeRealtimeCacheEngine: candidateEngine,
            reRecognizeWholeRecordingAfterStop: reRecognizeWholeRecordingAfterStop
        )

        recognitionUseCase.recognize(request: request) { outcome in
            completion(Self.outcome(
                from: outcome,
                candidateQuality: candidateQuality,
                shadowQuality: shadowQuality,
                reRecognizeWholeRecordingAfterStop: reRecognizeWholeRecordingAfterStop
            ))
        }
    }

    private static func outcome(
        from recognition: FinalRecognitionOutcome,
        candidateQuality: CandidateTranscriptQualityReport,
        shadowQuality: CandidateTranscriptQualityReport,
        reRecognizeWholeRecordingAfterStop: Bool
    ) -> FinalDeliveryOutcome {
        switch recognition {
        case .recognized(let result):
            return FinalDeliveryOutcome(
                text: result.text,
                source: result.engine,
                reason: reason(
                    forRecognizedEngine: result.engine,
                    candidateQuality: candidateQuality,
                    shadowQuality: shadowQuality,
                    reRecognizeWholeRecordingAfterStop: reRecognizeWholeRecordingAfterStop
                ),
                recognitionSeconds: result.recognitionSeconds
            )
        case .empty(let result):
            return FinalDeliveryOutcome(
                text: "",
                source: result.engine,
                reason: reason(
                    forRecognizedEngine: result.engine,
                    candidateQuality: candidateQuality,
                    shadowQuality: shadowQuality,
                    reRecognizeWholeRecordingAfterStop: reRecognizeWholeRecordingAfterStop
                ),
                recognitionSeconds: result.recognitionSeconds
            )
        case .failed(let message):
            return FinalDeliveryOutcome(
                text: "",
                source: "final-asr-failed",
                reason: message,
                recognitionSeconds: 0
            )
        }
    }

    private static func reason(
        forRecognizedEngine engine: String,
        candidateQuality: CandidateTranscriptQualityReport,
        shadowQuality: CandidateTranscriptQualityReport,
        reRecognizeWholeRecordingAfterStop: Bool
    ) -> String {
        let qualityText: String
        switch candidateQuality.decision {
        case .accept:
            qualityText = "quality=accepted quality_reason=accepted"
        case .reject(let reason):
            qualityText = "quality=rejected quality_reason=\(reason.rawValue)"
        }
        let shadowText: String
        switch shadowQuality.decision {
        case .accept:
            shadowText = "shadow_authority=disabled shadow_quality=accepted"
        case .reject(let reason):
            shadowText = "shadow_authority=disabled shadow_quality=rejected shadow_quality_reason=\(reason.rawValue)"
        }
        if engine == "realtime-preview-delivery-cache" {
            return "\(qualityText); \(shadowText); source=realtime_preview_delivery_cache complete cache selected; quality report is diagnostic"
        }
        if engine == "realtime-preview-delivery-cache-partial" {
            return "\(qualityText); \(shadowText); complete realtime cache was partial and delivered without UI fallback"
        }
        if engine.contains("complete-realtime-cache-shortfall-fallback") {
            return "\(qualityText); \(shadowText); final ASR implausibly shorter than complete realtime cache"
        }
        if engine.contains("complete-realtime-cache-fallback") {
            return "\(qualityText); \(shadowText); final ASR returned empty text; complete realtime cache used as safety net"
        }
        if engine == "realtime-preview-cache-unavailable" {
            return "\(qualityText); \(shadowText); realtime preview delivery cache unavailable; Final ASR disabled by user switch"
        }
        if reRecognizeWholeRecordingAfterStop {
            return "\(qualityText); \(shadowText); user requested full re-recognition after stop"
        }
        if candidateQuality.decision == .accept {
            return "\(qualityText); \(shadowText); realtime_preview_delivery_cache accepted but final ASR was authoritative for this path"
        }
        return "\(qualityText); \(shadowText); no realtime_preview_delivery_cache authority; final ASR authoritative"
    }
}
