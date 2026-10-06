import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

enum ASRBackend {
    case senseVoice
}

struct ASRConfiguration {
    let languageMode: RecognitionLanguageMode
    let backend: ASRBackend
}

// Task 3:把「候选缓存 vs 完整 final ASR」的最终交付选择从 SpeechInputCoordinator 拆成
// 独立 use case。断言计划里定义的分支，以及两轮真实录音发现问题后收紧的规则：
//   1. shadow-runtime-cache 候选 completed 也不能直接作为最终粘贴权威；该路径只保留为展示、
//      诊断与后续迁移对照。2026-07-19 产品复核确认：新候选路径产出的内容不可用。
//   2. 用户开启完整识别 -> final ASR，优先于以上候选权威规则
//   3. realtime-preview-delivery-cache 是唯一可交付实时缓存来源；
//      shadow-runtime-cache 不能压过它。
//   4. transcript running/failed/empty -> final ASR
//   5. online missing key(即候选缺失，走 legacy 兜底)-> 本地或 final fallback
// 见 docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md Task 3。

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
struct FinalDeliveryUseCaseCheck {
    static func main() {
        let configuration = ASRConfiguration(languageMode: .chinese, backend: .senseVoice)

        shadowRuntimeCandidateNeverWinsFinalPaste(configuration: configuration)
        badCompletedCandidateFallsBackToFinalASR(configuration: configuration)
        shadowRuntimeCandidateDoesNotSuppressRealtimeDeliveryCache(configuration: configuration)
        longRecordingShadowCandidateFallsBackToFullFinalASR(configuration: configuration)
        realtimeDeliveryCacheShortCandidateFallsBackToPreview(configuration: configuration)
        partialCompleteCacheReturnsOwnedText(configuration: configuration)
        missingCandidateFallsBackToFinalASR(configuration: configuration)
        userOptedFullReRecognitionBypassesDeliverableCandidate(configuration: configuration)
        realtimeDeliveryCacheUsedWhenShadowRuntimeMissing(configuration: configuration)

        print("FinalDeliveryUseCaseCheck passed")
    }

    private static func partialCompleteCacheReturnsOwnedText(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "不应该调用完整识别", "duration_sec": 0.4, "engine": "fake-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: nil,
            legacy: CandidateDeliverySnapshot(
                text: "完整缓存当前拥有的部分内容。",
                source: .realtimePreviewDeliveryCache,
                lifecycle: .running
            ),
            preview: "UI 里另一段可见文字不能参与交付。",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text == "完整缓存当前拥有的部分内容。")
        precondition(outcome.source == "realtime-preview-delivery-cache-partial")
        precondition(outcome.reason.contains("partial"))
        precondition(fake.transcribeCallCount == 0)
    }

    private static func deliver(
        useCase: FinalDeliveryUseCase,
        shadow: CandidateDeliverySnapshot?,
        legacy: CandidateDeliverySnapshot?,
        preview: String,
        reRecognize: Bool,
        configuration: ASRConfiguration,
        audioDuration: TimeInterval = 12.0
    ) -> FinalDeliveryOutcome {
        var captured: FinalDeliveryOutcome?
        useCase.deliver(
            taskID: UUID(),
            audioURL: URL(fileURLWithPath: "/tmp/final-delivery-check.wav"),
            configuration: configuration,
            audioDuration: audioDuration,
            shadowRuntimeSnapshot: shadow,
            realtimePreviewDeliverySnapshot: legacy,
            reRecognizeWholeRecordingAfterStop: reRecognize
        ) { outcome in captured = outcome }
        guard let captured else { preconditionFailure("delivery must complete synchronously in tests") }
        return captured
    }

    private static func shadowRuntimeCandidateNeverWinsFinalPaste(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "完整 final ASR 接管最终粘贴", "duration_sec": 0.4, "engine": "fake-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: CandidateDeliverySnapshot(
                text: "候选已完成且足够长的最终转录文本。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            legacy: nil,
            preview: "默认预览缓存比候选短",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text.isEmpty)
        precondition(outcome.source == "realtime-preview-cache-unavailable")
        precondition(outcome.reason.contains("shadow_authority=disabled"))
        precondition(!outcome.reason.contains("final ASR authoritative"))
        precondition(fake.transcribeCallCount == 0, "开关关闭时 shadow-runtime-cache 不可交付也不能偷偷调用完整 Final ASR")
    }

    private static func badCompletedCandidateFallsBackToFinalASR(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "代码设计排查一下到底哪里导致现在的问题。",
            "duration_sec": 0.5,
            "engine": "fake-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: CandidateDeliverySnapshot(
                text: "代码设计计排查查一下下到底哪里导致现在的问题。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            legacy: nil,
            preview: "代码设计排查一下到底哪里导致现在的问题。",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text.isEmpty)
        precondition(outcome.source == "realtime-preview-cache-unavailable")
        precondition(!outcome.reason.contains("final ASR authoritative"))
        precondition(fake.transcribeCallCount == 0, "开关关闭时坏候选不能触发完整 Final ASR")
    }

    private static func shadowRuntimeCandidateDoesNotSuppressRealtimeDeliveryCache(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "不应该调用完整识别", "duration_sec": 0.9, "engine": "fake-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: CandidateDeliverySnapshot(
                text: "shadow 候选即使完整也不再拥有最终权威",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            legacy: CandidateDeliverySnapshot(
                text: "生产实时缓存负责最终交付。",
                source: .realtimePreviewDeliveryCache,
                lifecycle: .completed
            ),
            preview: "",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text == "生产实时缓存负责最终交付。")
        precondition(outcome.source == "realtime-preview-delivery-cache")
        precondition(outcome.reason.contains("shadow_authority=disabled"))
        precondition(outcome.reason.contains("realtime_preview_delivery_cache"))
        precondition(fake.transcribeCallCount == 0, "生产实时缓存可交付时不应跑完整 final ASR")
    }

    private static func longRecordingShadowCandidateFallsBackToFullFinalASR(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "长录音最终交付由完整 final ASR 接管", "duration_sec": 0.6, "engine": "fake-long-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: CandidateDeliverySnapshot(
                text: "候选内容已经完成但不能再作为最终粘贴权威。",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            legacy: nil,
            preview: "候选内容已经完成。",
            reRecognize: false,
            configuration: configuration,
            audioDuration: 90.0
        )
        precondition(outcome.text.isEmpty)
        precondition(outcome.source == "realtime-preview-cache-unavailable")
        precondition(outcome.reason.contains("shadow_authority=disabled"))
        precondition(!outcome.reason.contains("final ASR authoritative"))
        precondition(fake.transcribeCallCount == 0, "开关关闭时长录音 shadow 候选不可交付也不能调用完整 Final ASR")
    }

    /// 完整生产缓存与 UI 可见文本不再互相比较；Final ASR 关闭时完整缓存直接交付。
    private static func realtimeDeliveryCacheShortCandidateFallsBackToPreview(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "完整识别接管了偏短的 legacy 候选", "duration_sec": 0.9, "engine": "fake-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: nil,
            legacy: CandidateDeliverySnapshot(
                text: "实时缓存更短",
                source: .realtimePreviewDeliveryCache,
                lifecycle: .completed
            ),
            preview: "默认缓存比候选更长，实时缓存不能偷渡成最终兜底。",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text == "实时缓存更短")
        precondition(outcome.source == "realtime-preview-delivery-cache")
        precondition(outcome.reason.contains("realtime_preview_delivery_cache"))
        precondition(!outcome.reason.contains("final ASR authoritative"))
        precondition(fake.transcribeCallCount == 0)
    }

    private static func missingCandidateFallsBackToFinalASR(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "候选缺失时完整识别兜底", "duration_sec": 0.6, "engine": "fake-empty-candidate",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let runningShadow = CandidateDeliverySnapshot(
            text: "还在跑，没有 completed",
            source: .shadowRuntimeCache,
            lifecycle: .running
        )
        let outcome = deliver(
            useCase: useCase,
            shadow: runningShadow,
            legacy: nil,
            preview: "",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text.isEmpty)
        precondition(outcome.source == "realtime-preview-cache-unavailable")
        precondition(outcome.reason.contains("Final ASR disabled"))
        precondition(!outcome.reason.contains("final ASR authoritative"))
        precondition(fake.transcribeCallCount == 0)
    }

    private static func userOptedFullReRecognitionBypassesDeliverableCandidate(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "开关开启时完整识别优先", "duration_sec": 1.1, "engine": "fake-force-final",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: CandidateDeliverySnapshot(
                text: "候选缓存本可直接交付",
                source: .shadowRuntimeCache,
                lifecycle: .completed
            ),
            legacy: nil,
            preview: "默认缓存",
            reRecognize: true,
            configuration: configuration
        )
        precondition(outcome.text == "开关开启时完整识别优先")
        precondition(outcome.source == "fake-force-final")
        precondition(fake.transcribeCallCount == 1, "用户开启整段重识别必须绕过候选缓存")
    }

    private static func realtimeDeliveryCacheUsedWhenShadowRuntimeMissing(configuration: ASRConfiguration) {
        let fake = FakeFinalASR(response: .success([
            "text": "不应该调用完整识别", "duration_sec": 0.4, "engine": "fake",
        ]))
        let useCase = FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake))
        let outcome = deliver(
            useCase: useCase,
            shadow: nil,
            legacy: CandidateDeliverySnapshot(
                text: "在线缺 Key 时生产实时缓存兜底交付。",
                source: .realtimePreviewDeliveryCache,
                lifecycle: .completed
            ),
            preview: "",
            reRecognize: false,
            configuration: configuration
        )
        precondition(outcome.text == "在线缺 Key 时生产实时缓存兜底交付。")
        precondition(outcome.source == "realtime-preview-delivery-cache")
        precondition(outcome.reason.contains("realtime_preview_delivery_cache"))
        precondition(fake.transcribeCallCount == 0)
    }
}
