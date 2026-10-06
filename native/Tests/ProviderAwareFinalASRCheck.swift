import Foundation

enum RecognitionLanguageMode { case chinese }
enum ASRBackend {
    case senseVoice, parakeetSherpa, funASRNano, qwen3MLX06B, qwen3MLX17B

    var displayName: String {
        switch self {
        case .funASRNano: return "Fun-ASR Nano"
        default: return String(describing: self)
        }
    }
}
struct ASRConfiguration { let languageMode: RecognitionLanguageMode; let backend: ASRBackend }
protocol FinalASRTranscribing: AnyObject {
    func transcribe(audio: URL, configuration: ASRConfiguration, completion: @escaping (Result<[String: Any], Error>) -> Void)
}
enum LaunchDiagnostics { static func mark(_ message: String) {} }

private final class FakeSenseVoice: FinalASRTranscribing {
    var callCount = 0
    func transcribe(audio: URL, configuration: ASRConfiguration, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        callCount += 1
        completion(.success(["text": "SenseVoice 结果", "engine": "sensevoice", "duration_sec": 0.1]))
    }
}

private final class FakeSidecar: FunASRSidecarTranscribing {
    var warmupResult: Result<String, Error> = .success("fun-asr-nano-2512/fake")
    var transcriptionResult: Result<FunASRTranscriptionResult, Error> = .success(.init(text: "FunASR 结果", engine: "fun-asr-nano-2512/fake", durationSeconds: 0.2))
    func warmUp(providerID: String, modelDirectory: URL, completion: @escaping (Result<String, Error>) -> Void) {
        completion(warmupResult)
    }
    func transcribe(providerID: String, audioURL: URL, hotwords: [String], completion: @escaping (Result<FunASRTranscriptionResult, Error>) -> Void) {
        completion(transcriptionResult)
    }
    func stop() {}
}

private final class FakeUnifiedLocalASR: LocalASRRunning {
    var transcriptionResult: Result<ASREngineResult, Error> = .failure(
        NSError(domain: "test.unified", code: 1)
    )
    private(set) var requestedCandidates: [ASRCandidateID] = []

    func probe(_ descriptor: ASRModelDescriptor) -> ASRReadiness { .ready }
    func warmUp(
        candidate: ASRModelDescriptor,
        hotwords: [String],
        completion: @escaping (Result<Double, Error>) -> Void
    ) {
        completion(.success(0))
    }
    func transcribe(
        candidate: ASRModelDescriptor,
        audioURL: URL,
        hotwords: [String],
        completion: @escaping (Result<ASREngineResult, Error>) -> Void
    ) {
        requestedCandidates.append(candidate.id)
        completion(transcriptionResult)
    }
    func cancel(runID: UUID) {}
    func unload(completion: @escaping () -> Void) { completion() }
}

@main
struct ProviderAwareFinalASRCheck {
    static func main() {
        let audio = URL(fileURLWithPath: "/tmp/audio.wav")
        let senseVoice = FakeSenseVoice()
        let sidecar = FakeSidecar()
        let router = ProviderAwareFinalASR(
            senseVoice: senseVoice,
            sidecar: sidecar,
            modelDirectory: { _ in URL(fileURLWithPath: "/tmp/model") },
            hotwords: { ["Qwen3-ASR"] }
        )

        let native = wait { router.transcribe(audio: audio, configuration: .init(languageMode: .chinese, backend: .senseVoice), completion: $0) }
        precondition(text(native) == "SenseVoice 结果")
        precondition(senseVoice.callCount == 1)

        let enhanced = wait { router.transcribe(audio: audio, configuration: .init(languageMode: .chinese, backend: .funASRNano), completion: $0) }
        precondition(text(enhanced) == "FunASR 结果")
        precondition(senseVoice.callCount == 1)

        sidecar.transcriptionResult = .failure(NSError(domain: "test", code: 1))
        let failed = wait { router.transcribe(audio: audio, configuration: .init(languageMode: .chinese, backend: .funASRNano), completion: $0) }
        precondition(isFailure(failed), "selected provider failure must remain a failure")
        precondition(errorDescription(failed) == "Fun-ASR Nano 识别失败，请重试。")
        precondition(senseVoice.callCount == 1, "selected provider failure must not call SenseVoice")

        let missingRouter = ProviderAwareFinalASR(
            senseVoice: senseVoice,
            sidecar: sidecar,
            modelDirectory: { _ in nil },
            hotwords: { [] }
        )
        let missing = wait { missingRouter.transcribe(audio: audio, configuration: .init(languageMode: .chinese, backend: .funASRNano), completion: $0) }
        precondition(isFailure(missing), "missing selected model must remain a failure")
        precondition(errorDescription(missing) == "Fun-ASR Nano 尚未就绪，请在设置中检查模型下载状态。")
        precondition(senseVoice.callCount == 1, "missing selected model must not call SenseVoice")

        verifyUnifiedProviderFailuresDoNotFallBack(
            audio: audio,
            senseVoice: senseVoice
        )
        print("ProviderAwareFinalASRCheck passed")
    }

    private static func verifyUnifiedProviderFailuresDoNotFallBack(
        audio: URL,
        senseVoice: FakeSenseVoice
    ) {
        let unified = FakeUnifiedLocalASR()
        let backends: [(ASRBackend, ASRCandidateID, ASREngineKind)] = [
            (.parakeetSherpa, .parakeetTDT06B, .sherpa),
            (.funASRNano, .funASRNano2512, .funASR),
            (.qwen3MLX06B, .qwen3MLX06B, .mlx),
            (.qwen3MLX17B, .qwen3MLX17B, .mlx),
        ]
        let descriptors = Dictionary(uniqueKeysWithValues: backends.map { backend, candidate, engine in
            (String(describing: backend), descriptor(id: candidate, engine: engine))
        })
        let router = ProviderAwareFinalASR(
            senseVoice: senseVoice,
            unified: unified,
            descriptor: { descriptors[String(describing: $0)] },
            hotwords: { ["Codex"] }
        )
        let senseVoiceCallsBeforeMatrix = senseVoice.callCount

        for (backend, candidate, _) in backends {
            let result = wait {
                router.transcribe(
                    audio: audio,
                    configuration: .init(languageMode: .chinese, backend: backend),
                    completion: $0
                )
            }
            precondition(isFailure(result), "\(backend) failure must remain a failure")
            precondition(
                errorDescription(result) == "\(backend.displayName) 识别失败，请重试。",
                "\(backend) must surface its own failure"
            )
            precondition(
                unified.requestedCandidates.last == candidate,
                "\(backend) must execute its selected candidate"
            )
            precondition(
                senseVoice.callCount == senseVoiceCallsBeforeMatrix,
                "\(backend) failure must not call SenseVoice"
            )
        }
    }

    private static func descriptor(
        id: ASRCandidateID,
        engine: ASREngineKind
    ) -> ASRModelDescriptor {
        ASRModelDescriptor(
            id: id,
            displayName: id.rawValue,
            engine: engine,
            modelDirectory: URL(fileURLWithPath: "/tmp/\(id.rawValue)"),
            requiredRelativePaths: [],
            hotwordStrategy: .unsupported,
            readiness: .ready,
            productionReady: true
        )
    }

    private static func text(_ result: Result<[String: Any], Error>) -> String {
        guard case .success(let value) = result else { return "" }
        return value["text"] as? String ?? ""
    }

    private static func isFailure(_ result: Result<[String: Any], Error>) -> Bool {
        guard case .failure = result else { return false }
        return true
    }

    private static func errorDescription(_ result: Result<[String: Any], Error>) -> String {
        guard case .failure(let error) = result else { return "" }
        return error.localizedDescription
    }

    private static func wait(_ operation: (@escaping (Result<[String: Any], Error>) -> Void) -> Void) -> Result<[String: Any], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error>!
        operation { result = $0; semaphore.signal() }
        precondition(semaphore.wait(timeout: .now() + 2) == .success)
        return result
    }
}
