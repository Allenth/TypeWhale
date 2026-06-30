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
        transcriber.transcribe(
            audio: request.audioURL,
            configuration: request.configuration
        ) { response in
            completion(Self.resolve(response, languageMode: request.configuration.languageMode))
        }
    }

    static func resolve(
        _ response: Result<[String: Any], Error>,
        languageMode: RecognitionLanguageMode
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
            return isMeaningfulRecognitionText(text) ? .recognized(result) : .empty(result)
        }
    }
}
