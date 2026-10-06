import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

enum ASRBackend {
    case senseVoice
    case funASRNano
}

struct ASRConfiguration {
    let languageMode: RecognitionLanguageMode
    let backend: ASRBackend
}

private final class FakeFinalASR: FinalASRTranscribing {
    var response: Result<[String: Any], Error>
    private(set) var transcribeCallCount = 0

    init(response: Result<[String: Any], Error>) {
        self.response = response
    }

    func transcribe(
        audio: URL,
        configuration: ASRConfiguration,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        transcribeCallCount += 1
        completion(response)
    }
}

@main
struct FinalRecognitionUseCaseCheck {
    static func main() {
        let configuration = ASRConfiguration(languageMode: .chinese, backend: .senseVoice)

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
            .success(["text": "The.", "duration_sec": 0.2, "engine": "stub"]),
            languageMode: .chinese
        ) {
        case .empty(let result):
            precondition(result.text == "The.")
            precondition(result.recognitionSeconds == 0.2)
        default:
            preconditionFailure("expected The. silence hallucination to be empty")
        }

        switch FinalRecognitionUseCase.resolve(
            .success(["text": "", "duration_sec": 1.64, "engine": "sensevoice-small/sherpa-native"]),
            languageMode: .chinese,
            completeRealtimeCacheText: "完整缓存已经有内容，最终识别为空时不能粘贴空。"
        ) {
        case .recognized(let result):
            precondition(result.text == "完整缓存已经有内容，最终识别为空时不能粘贴空。")
            precondition(result.recognitionSeconds == 1.64)
            precondition(result.engine == "sensevoice-small/sherpa-native+complete-realtime-cache-fallback")
        default:
            preconditionFailure("expected realtime preview fallback when final ASR is empty")
        }

        let longPreview = String(repeating: "这是一段用于模拟两分钟实时预览的长文本，", count: 16)
        switch FinalRecognitionUseCase.resolve(
            .success(["text": "这里最终只有十七字", "duration_sec": 3.16, "engine": "sensevoice-small/sherpa-native"]),
            languageMode: .chinese,
            completeRealtimeCacheText: longPreview
        ) {
        case .recognized(let result):
            precondition(result.text == longPreview)
            precondition(result.recognitionSeconds == 3.16)
            precondition(result.engine == "sensevoice-small/sherpa-native+complete-realtime-cache-shortfall-fallback")
        default:
            preconditionFailure("expected realtime preview fallback when final ASR is implausibly shorter than long preview")
        }

        switch FinalRecognitionUseCase.resolve(
            .success(["text": "这是一段正常的短句", "duration_sec": 0.8, "engine": "sensevoice-small/sherpa-native"]),
            languageMode: .chinese,
            completeRealtimeCacheText: "这是一段正常的短句，然后完整缓存里稍微多了几个字"
        ) {
        case .recognized(let result):
            precondition(result.text == "这是一段正常的短句")
            precondition(result.engine == "sensevoice-small/sherpa-native")
        default:
            preconditionFailure("short utterances must keep final ASR authority")
        }

        switch FinalRecognitionUseCase.resolve(
            .success(["text": "", "duration_sec": 1.64, "engine": "sensevoice-small/sherpa-native"]),
            languageMode: .chinese,
            completeRealtimeCacheText: "。"
        ) {
        case .empty:
            break
        default:
            preconditionFailure("punctuation-only preview fallback must not become final text")
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
                audioDuration: 1.0,
                reRecognizeWholeRecordingAfterStop: true
            )
        ) { outcome in
            delivered = outcome
        }

        guard case .recognized(let result) = delivered else {
            preconditionFailure("expected fake transcriber result")
        }
        precondition(result.text == "hello")
        precondition(result.engine == "fake")
        precondition(fake.transcribeCallCount == 1)

        let previewFirstFake = FakeFinalASR(response: .success([
            "text": "开关关闭时不应该调用完整识别",
            "duration_sec": 0.4,
            "engine": "fake",
        ]))
        let previewFirstUseCase = FinalRecognitionUseCase(transcriber: previewFirstFake)
        var previewFirstDelivered: FinalRecognitionOutcome?
        previewFirstUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-preview-first.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "这段完整实时缓存应该直接成为最终交付文本。",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            previewFirstDelivered = outcome
        }
        guard case .recognized(let previewResult) = previewFirstDelivered else {
            preconditionFailure("expected complete realtime cache when Final ASR switch is off")
        }
        precondition(previewResult.text == "这段完整实时缓存应该直接成为最终交付文本。")
        precondition(previewResult.engine == "realtime-preview-delivery-cache")
        precondition(previewFirstFake.transcribeCallCount == 0)

        let funASRFake = FakeFinalASR(response: .success([
            "text": "Fun-ASR 自己的较短结果",
            "duration_sec": 0.8,
            "engine": "fun-asr-nano-2512/funasr-python",
        ]))
        let funASRUseCase = FinalRecognitionUseCase(transcriber: funASRFake)
        var funASRDelivered: FinalRecognitionOutcome?
        funASRUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-funasr.wav"),
                configuration: ASRConfiguration(languageMode: .chinese, backend: .funASRNano),
                audioDuration: 12.0,
                completeRealtimeCacheText: String(repeating: "SenseVoice 实时缓存更长但不能替代所选模型。", count: 8),
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            funASRDelivered = outcome
        }
        guard case .recognized(let funASRResult) = funASRDelivered else {
            preconditionFailure("selected Fun-ASR must produce the final result")
        }
        precondition(funASRResult.text == "Fun-ASR 自己的较短结果")
        precondition(funASRResult.engine == "fun-asr-nano-2512/funasr-python")
        precondition(funASRFake.transcribeCallCount == 1)

        let failedFunASRFake = FakeFinalASR(response: .failure(NSError(
            domain: "test.funasr",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "所选识别模型运行失败：测试错误"]
        )))
        let failedFunASRUseCase = FinalRecognitionUseCase(transcriber: failedFunASRFake)
        var failedFunASRDelivered: FinalRecognitionOutcome?
        failedFunASRUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-funasr-failed.wav"),
                configuration: ASRConfiguration(languageMode: .chinese, backend: .funASRNano),
                audioDuration: 12.0,
                completeRealtimeCacheText: "即使实时缓存完整，也不能在所选模型失败后自动顶替。",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            failedFunASRDelivered = outcome
        }
        guard case .failed(let failedMessage) = failedFunASRDelivered else {
            preconditionFailure("selected Fun-ASR failure must remain a failure")
        }
        precondition(failedMessage.contains("所选识别模型运行失败"))
        precondition(failedFunASRFake.transcribeCallCount == 1)

        let invalidPreviewFake = FakeFinalASR(response: .success([
            "text": "开关关闭时预览无效也不应该完整识别兜底",
            "duration_sec": 0.7,
            "engine": "fake-fallback",
        ]))
        let invalidPreviewUseCase = FinalRecognitionUseCase(transcriber: invalidPreviewFake)
        var invalidPreviewDelivered: FinalRecognitionOutcome?
        invalidPreviewUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-invalid-preview.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "。",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            invalidPreviewDelivered = outcome
        }
        guard case .empty(let fallbackResult) = invalidPreviewDelivered else {
            preconditionFailure("expected unavailable realtime cache when preview cache is invalid and Final ASR switch is off")
        }
        precondition(fallbackResult.text.isEmpty)
        precondition(fallbackResult.engine == "realtime-preview-cache-unavailable")
        precondition(invalidPreviewFake.transcribeCallCount == 0)

        let candidateFirstFake = FakeFinalASR(response: .success([
            "text": "不应该调用完整识别",
            "duration_sec": 0.4,
            "engine": "fake",
        ]))
        let candidateFirstUseCase = FinalRecognitionUseCase(transcriber: candidateFirstFake)
        var candidateFirstDelivered: FinalRecognitionOutcome?
        candidateFirstUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-candidate-first.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "完整缓存保留了最后一句。",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            candidateFirstDelivered = outcome
        }
        guard case .recognized(let candidateResult) = candidateFirstDelivered else {
            preconditionFailure("expected candidate preview cache to become final text")
        }
        precondition(candidateResult.text == "完整缓存保留了最后一句。")
        precondition(candidateResult.engine == "realtime-preview-delivery-cache")
        precondition(candidateFirstFake.transcribeCallCount == 0)

        let invalidCandidateFake = FakeFinalASR(response: .success([
            "text": "开关关闭时候选无效不能跑完整 final ASR",
            "duration_sec": 0.9,
            "engine": "fake-final",
        ]))
        let invalidCandidateUseCase = FinalRecognitionUseCase(transcriber: invalidCandidateFake)
        var invalidCandidateDelivered: FinalRecognitionOutcome?
        invalidCandidateUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-invalid-candidate.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "。",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            invalidCandidateDelivered = outcome
        }
        guard case .empty(let invalidCandidateResult) = invalidCandidateDelivered else {
            preconditionFailure("expected unavailable result when complete cache is invalid and Final ASR switch is off")
        }
        precondition(invalidCandidateResult.text.isEmpty)
        precondition(invalidCandidateResult.engine == "realtime-preview-cache-unavailable")
        precondition(invalidCandidateFake.transcribeCallCount == 0)

        let shortCandidateFake = FakeFinalASR(response: .success([
            "text": "",
            "duration_sec": 0.9,
            "engine": "fake-empty-final",
        ]))
        let shortCandidateUseCase = FinalRecognitionUseCase(transcriber: shortCandidateFake)
        var shortCandidateDelivered: FinalRecognitionOutcome?
        shortCandidateUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-short-candidate.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "完整缓存更短",
                reRecognizeWholeRecordingAfterStop: false
            )
        ) { outcome in
            shortCandidateDelivered = outcome
        }
        guard case .recognized(let shortCandidateResult) = shortCandidateDelivered else {
            preconditionFailure("expected complete realtime cache when Final ASR switch is off")
        }
        precondition(shortCandidateResult.text == "完整缓存更短")
        precondition(shortCandidateResult.engine == "realtime-preview-delivery-cache")
        precondition(shortCandidateFake.transcribeCallCount == 0)

        let forceFinalFake = FakeFinalASR(response: .success([
            "text": "开关开启时完整识别优先",
            "duration_sec": 1.1,
            "engine": "fake-force-final",
        ]))
        let forceFinalUseCase = FinalRecognitionUseCase(transcriber: forceFinalFake)
        var forceFinalDelivered: FinalRecognitionOutcome?
        forceFinalUseCase.recognize(
            request: FinalRecognitionRequest(
                taskID: UUID(),
                audioURL: URL(fileURLWithPath: "/tmp/final-recognition-force-final.wav"),
                configuration: configuration,
                audioDuration: 12.0,
                completeRealtimeCacheText: "完整缓存",
                reRecognizeWholeRecordingAfterStop: true
            )
        ) { outcome in
            forceFinalDelivered = outcome
        }
        guard case .recognized(let forceFinalResult) = forceFinalDelivered else {
            preconditionFailure("expected force-final switch to bypass candidate cache")
        }
        precondition(forceFinalResult.text == "开关开启时完整识别优先")
        precondition(forceFinalResult.engine == "fake-force-final")
        precondition(forceFinalFake.transcribeCallCount == 1)
    }
}
