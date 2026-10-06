import Foundation

protocol FunASRSidecarTranscribing: AnyObject {
    func warmUp(
        providerID: String,
        modelDirectory: URL,
        completion: @escaping (Result<String, Error>) -> Void
    )
    func transcribe(
        providerID: String,
        audioURL: URL,
        hotwords: [String],
        completion: @escaping (Result<FunASRTranscriptionResult, Error>) -> Void
    )
    func stop()
}

extension FunASRSidecar: FunASRSidecarTranscribing {}

final class ManagedFunASRSidecarAdapter: FunASRSidecarTranscribing {
    private let runtimeRoot: URL
    private let workerURL: URL
    private let lock = NSLock()
    private var activeSidecar: FunASRSidecar?

    init(runtimeRoot: URL, workerURL: URL) {
        self.runtimeRoot = runtimeRoot
        self.workerURL = workerURL
    }

    func warmUp(
        providerID: String,
        modelDirectory: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        do {
            let sidecar = try resolveSidecar()
            sidecar.warmUp(
                providerID: providerID,
                modelDirectory: modelDirectory,
                completion: completion
            )
        } catch {
            completion(.failure(error))
        }
    }

    func transcribe(
        providerID: String,
        audioURL: URL,
        hotwords: [String],
        completion: @escaping (Result<FunASRTranscriptionResult, Error>) -> Void
    ) {
        do {
            let sidecar = try resolveSidecar()
            sidecar.transcribe(
                providerID: providerID,
                audioURL: audioURL,
                hotwords: hotwords,
                completion: completion
            )
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        lock.lock()
        let sidecar = activeSidecar
        activeSidecar = nil
        lock.unlock()
        sidecar?.stop()
    }

    private func resolveSidecar() throws -> FunASRSidecar {
        lock.lock()
        defer { lock.unlock() }
        if let activeSidecar { return activeSidecar }
        let runtime = ManagedFunASRRuntime(rootURL: runtimeRoot)
        guard case .ready(let pythonURL) = runtime.state else {
            throw NSError(
                domain: "com.waykingah.typewhale.managed-funasr-sidecar",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "FunASR 运行环境尚未安装或校验失败"]
            )
        }
        guard FileManager.default.fileExists(atPath: workerURL.path) else {
            throw NSError(
                domain: "com.waykingah.typewhale.managed-funasr-sidecar",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "FunASR worker 缺失"]
            )
        }
        let sidecar = FunASRSidecar(pythonURL: pythonURL, workerURL: workerURL)
        activeSidecar = sidecar
        return sidecar
    }
}

final class ProviderAwareFinalASR: FinalASRTranscribing {
    typealias ModelDirectoryResolver = (ASRBackend) -> URL?

    private let senseVoice: FinalASRTranscribing
    private let sidecar: FunASRSidecarTranscribing?
    private let modelDirectory: ModelDirectoryResolver
    private let hotwords: () -> [String]
    private let unified: LocalASRRunning?
    private let descriptor: ((ASRBackend) -> ASRModelDescriptor?)?

    init(
        senseVoice: FinalASRTranscribing,
        sidecar: FunASRSidecarTranscribing,
        modelDirectory: @escaping ModelDirectoryResolver,
        hotwords: @escaping () -> [String]
    ) {
        self.senseVoice = senseVoice
        self.sidecar = sidecar
        self.modelDirectory = modelDirectory
        self.hotwords = hotwords
        self.unified = nil
        self.descriptor = nil
    }

    init(
        senseVoice: FinalASRTranscribing,
        unified: LocalASRRunning,
        descriptor: @escaping (ASRBackend) -> ASRModelDescriptor?,
        hotwords: @escaping () -> [String]
    ) {
        self.senseVoice = senseVoice
        self.sidecar = nil
        self.modelDirectory = { _ in nil }
        self.hotwords = hotwords
        self.unified = unified
        self.descriptor = descriptor
    }

    func transcribe(
        audio: URL,
        configuration: ASRConfiguration,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard configuration.backend != .senseVoice else {
            senseVoice.transcribe(audio: audio, configuration: configuration, completion: completion)
            return
        }
        if let unified {
            let gate = ASRCompletionGate(completion)
            guard let candidate=descriptor?(configuration.backend) else {
                failSelectedProvider(
                    backend: configuration.backend,
                    reason: "model_unavailable",
                    completion: gate.complete
                )
                return
            }
            let frozenHotwords=productionHotwords(for: candidate)
            unified.transcribe(candidate:candidate,audioURL:audio,hotwords:frozenHotwords) { [weak self] result in
                guard let self else { return }; switch result {
                case .success(let value): gate.complete(.success(["text":value.text,"engine":value.engine,"duration_sec":value.inferenceSeconds,"requested":candidate.id.rawValue,"actual":candidate.id.rawValue,"fallback_count":0]))
                case .failure(let error):
                    self.failSelectedProvider(
                        backend: configuration.backend,
                        reason: "target_failed:\(error.localizedDescription)",
                        completion: gate.complete
                    )
                }
            }
            return
        }
        guard let providerID = providerID(for: configuration.backend),
              let directory = modelDirectory(configuration.backend) else {
            failSelectedProvider(
                backend: configuration.backend,
                reason: "model_unavailable",
                completion: completion
            )
            return
        }

        guard let sidecar else {
            failSelectedProvider(
                backend: configuration.backend,
                reason: "sidecar_unavailable",
                completion: completion
            )
            return
        }
        sidecar.warmUp(
            providerID: providerID,
            modelDirectory: directory
        ) { [weak self] warmup in
            guard let self else { return }
            switch warmup {
            case .failure(let error):
                failSelectedProvider(
                    backend: configuration.backend,
                    reason: "warmup_failed:\(error.localizedDescription)",
                    completion: completion
                )
            case .success:
                sidecar.transcribe(
                    providerID: providerID,
                    audioURL: audio,
                    hotwords: productionHotwords()
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let value):
                        completion(.success([
                            "text": value.text,
                            "engine": value.engine,
                            "duration_sec": value.durationSeconds,
                        ]))
                    case .failure(let error):
                        failSelectedProvider(
                            backend: configuration.backend,
                            reason: "transcribe_failed:\(error.localizedDescription)",
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    func warmUp(backend: ASRBackend, completion: ((Result<String, Error>) -> Void)? = nil) {
        if let unified, let candidate=descriptor?(backend) {
            unified.warmUp(candidate:candidate,hotwords:productionHotwords(for: candidate)) { completion?($0.map { _ in candidate.id.rawValue }) }
            return
        }
        guard backend != .senseVoice,
              let providerID = providerID(for: backend),
              let directory = modelDirectory(backend) else {
            completion?(.failure(NSError(
                domain: "com.waykingah.typewhale.provider-aware-asr",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "FunASR 模型或运行环境不可用"]
            )))
            return
        }
        guard let sidecar else { completion?(.failure(NSError(domain:"com.waykingah.typewhale.provider-aware-asr",code:2,userInfo:[NSLocalizedDescriptionKey:"识别引擎不可用"]))); return }
        sidecar.warmUp(
            providerID: providerID,
            modelDirectory: directory
        ) { completion?($0) }
    }

    func stop() {
        sidecar?.stop()
        unified?.unload(completion: {})
    }

    private func productionHotwords() -> [String] {
        Array(hotwords().prefix(64))
    }

    private func productionHotwords(for candidate: ASRModelDescriptor) -> [String] {
        let words = productionHotwords()
        guard candidate.hotwordStrategy == .nativeSpaceSeparated else { return words }
        let accepted = words.filter {
            $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }
        let skipped = words.count - accepted.count
        if skipped > 0 {
            LaunchDiagnostics.mark(
                "asr_hotwords_filtered provider=\(candidate.id.rawValue) skipped=\(skipped) accepted=\(accepted.count) reason=space_separated_format"
            )
        }
        return accepted
    }

    private func failSelectedProvider(
        backend: ASRBackend,
        reason: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        LaunchDiagnostics.mark(
            "final_asr_failed selected_backend=\(String(describing: backend)) reason=\(reason)"
        )
        let message: String
        if reason == "model_unavailable" || reason == "sidecar_unavailable" {
            message = "\(backend.displayName) 尚未就绪，请在设置中检查模型下载状态。"
        } else {
            message = "\(backend.displayName) 识别失败，请重试。"
        }
        completion(.failure(NSError(
            domain: "com.waykingah.typewhale.provider-aware-asr",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: message
            ]
        )))
    }

    private func providerID(for backend: ASRBackend) -> String? {
        switch backend {
        case .senseVoice, .parakeetSherpa, .qwen3MLX06B, .qwen3MLX17B: return nil
        case .funASRNano: return "fun-asr-nano-2512"
        }
    }
}

private final class ASRCompletionGate: @unchecked Sendable {
    private let lock=NSLock(); private var completed=false
    private let completion:(Result<[String:Any],Error>)->Void
    init(_ completion:@escaping(Result<[String:Any],Error>)->Void){self.completion=completion}
    func complete(_ result:Result<[String:Any],Error>){lock.lock();guard !completed else{lock.unlock();return};completed=true;lock.unlock();completion(result)}
}
