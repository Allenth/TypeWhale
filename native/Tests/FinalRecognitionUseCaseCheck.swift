import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

struct ASRConfiguration {
    let languageMode: RecognitionLanguageMode
}

private final class FakeFinalASR: FinalASRTranscribing {
    var response: Result<[String: Any], Error>

    init(response: Result<[String: Any], Error>) {
        self.response = response
    }

    func transcribe(
        audio: URL,
        configuration: ASRConfiguration,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        completion(response)
    }
}

@main
struct FinalRecognitionUseCaseCheck {
    static func main() {
        let configuration = ASRConfiguration(languageMode: .chinese)

        switch FinalRecognitionUseCase.resolve(
            .success(["text": "，目前的这些功能的话都是同行玩剩下的。", "duration_sec": 1.25, "engine": "stub"]),
            languageMode: .chinese
        ) {
        case .recognized(let result):
            precondition(result.text == "目前的这些功能的话都是同行玩剩下的。")
            precondition(result.recognitionSeconds == 1.25)
            precondition(result.engine == "stub")
        default:
            preconditionFailure("expected recognized final ASR result")
        }

        switch FinalRecognitionUseCase.resolve(
            .success(["text": "嗯", "duration_sec": 0.2, "engine": "stub"]),
            languageMode: .chinese
        ) {
        case .empty(let result):
            precondition(result.text == "嗯")
            precondition(result.recognitionSeconds == 0.2)
        default:
            preconditionFailure("expected empty final ASR result")
        }

        switch FinalRecognitionUseCase.resolve(
            .success(["error": "model unavailable"]),
            languageMode: .chinese
        ) {
        case .failed(let message):
            precondition(message == "model unavailable")
        default:
            preconditionFailure("expected failed final ASR result")
        }

        let fake = FakeFinalASR(response: .success([
            "text": "...hello",
            "duration_sec": 0.4,
            "engine": "fake",
        ]))
        let useCase = FinalRecognitionUseCase(transcriber: fake)
        var delivered: FinalRecognitionOutcome?
        useCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-check.wav"),
                configuration: configuration,
                audioDuration: 1.0
            )
        ) { outcome in
            delivered = outcome
        }

        guard case .recognized(let result) = delivered else {
            preconditionFailure("expected fake transcriber result")
        }
        precondition(result.text == "hello")
        precondition(result.engine == "fake")
    }
}
