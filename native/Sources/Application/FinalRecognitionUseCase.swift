import Foundation

protocol FinalASRTranscribing: AnyObject {
    func transcribe(
        audio: URL,
        configuration: ASRConfiguration,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    )
}

struct FinalRecognitionRequest {
    let taskID: UUID
    let audioURL: URL
    let configuration: ASRConfiguration
    let audioDuration: TimeInterval
    var completeRealtimeCacheText: String = ""
    var completeRealtimeCacheEngine: String = "realtime-preview-delivery-cache"
    var reRecognizeWholeRecordingAfterStop: Bool = false
}

struct FinalRecognitionResult {
    let text: String
    let recognitionSeconds: Double
    let engine: String
}

enum FinalRecognitionOutcome {
    case recognized(FinalRecognitionResult)
    case empty(FinalRecognitionResult)
    case failed(String)
}

struct FinalRecognitionUseCase {
    let transcriber: FinalASRTranscribing

    func recognize(
        request: FinalRecognitionRequest,
        completion: @escaping (FinalRecognitionOutcome) -> Void
    ) {
        let completeCacheText = Self.completeRealtimeCacheResultText(
            request.completeRealtimeCacheText,
            languageMode: request.configuration.languageMode
        )
        let authority = FinalRecognitionAuthorityPolicy.action(
            backend: request.configuration.backend,
            reRecognizeWholeRecordingAfterStop: request.reRecognizeWholeRecordingAfterStop,
            realtimeCacheReady: isMeaningfulRecognitionText(completeCacheText)
        )
        if authority == .useRealtimeCache {
            completion(.recognized(FinalRecognitionResult(
                text: completeCacheText,
                recognitionSeconds: 0,
                engine: request.completeRealtimeCacheEngine
            )))
            return
        }
        if authority == .realtimeCacheUnavailable {
            completion(.empty(FinalRecognitionResult(
                text: "",
                recognitionSeconds: 0,
                engine: "realtime-preview-cache-unavailable"
            )))
            return
        }

        let allowedFallbackText = request.configuration.backend == .senseVoice
            ? completeCacheText
            : ""
        transcriber.transcribe(
            audio: request.audioURL,
            configuration: request.configuration
        ) { response in
            completion(Self.resolve(
                response,
                languageMode: request.configuration.languageMode,
                completeRealtimeCacheText: allowedFallbackText
            ))
        }
    }

    static func completeRealtimeCacheResultText(
        _ text: String,
        languageMode: RecognitionLanguageMode
    ) -> String {
        cleanRecognitionText(text, languageMode: languageMode)
    }

    static func resolve(
        _ response: Result<[String: Any], Error>,
        languageMode: RecognitionLanguageMode,
        completeRealtimeCacheText: String = ""
    ) -> FinalRecognitionOutcome {
        switch response {
        case .failure(let error):
            return .failed(error.localizedDescription)
        case .success(let value):
            if let error = value["error"] as? String, !error.isEmpty {
                return .failed(error)
            }
            let text = cleanRecognitionText(value["text"] as? String ?? "", languageMode: languageMode)
            let result = FinalRecognitionResult(
                text: text,
                recognitionSeconds: value["duration_sec"] as? Double ?? 0,
                engine: value["engine"] as? String ?? "--"
            )
            let fallback = cleanRecognitionText(completeRealtimeCacheText, languageMode: languageMode)
            if isMeaningfulRecognitionText(text) {
                if shouldUseCompleteRealtimeCacheFallback(finalText: text, completeCacheText: fallback) {
                    return .recognized(FinalRecognitionResult(
                        text: fallback,
                        recognitionSeconds: result.recognitionSeconds,
                        engine: "\(result.engine)+complete-realtime-cache-shortfall-fallback"
                    ))
                }
                return .recognized(result)
            }
            guard isMeaningfulRecognitionText(fallback) else { return .empty(result) }
            return .recognized(FinalRecognitionResult(
                text: fallback,
                recognitionSeconds: result.recognitionSeconds,
                engine: "\(result.engine)+complete-realtime-cache-fallback"
            ))
        }
    }

    private static func shouldUseCompleteRealtimeCacheFallback(
        finalText: String,
        completeCacheText: String
    ) -> Bool {
        guard isMeaningfulRecognitionText(completeCacheText) else { return false }

        let finalCount = finalText.count
        let previewCount = completeCacheText.count

        // For short utterances, the final ASR may legitimately be more compact than the
        // realtime preview. Only treat this as a long-recording shortfall once the preview
        // has accumulated enough text and the gap is large enough to be product-visible.
        guard previewCount >= 100 else { return false }
        guard previewCount - finalCount >= 80 else { return false }

        let allowedMinimum = max(40, Int(Double(previewCount) * 0.35))
        return finalCount < allowedMinimum
    }

}
