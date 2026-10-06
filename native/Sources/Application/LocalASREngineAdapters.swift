import Foundation

extension SherpaBenchmarkAdapter: LocalASREngineRunning {
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void) { run(request: request, completion: completion) }
}

final class SherpaLocalEngineAdapter: LocalASREngineRunning {
    private let sidecar: SherpaASRSidecar
    init(sidecar: SherpaASRSidecar) { self.sidecar = sidecar }

    func warmUp(_ descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload, completion: @escaping (Result<Double, Error>) -> Void) {
        guard hotwords == .none else { completion(.failure(error("Sherpa helper 候选不接受热词"))); return }
        let started = ProcessInfo.processInfo.systemUptime
        sidecar.warmUp(providerID: descriptor.id.rawValue, modelDirectory: descriptor.modelDirectory) {
            completion($0.map { _ in ProcessInfo.processInfo.systemUptime - started })
        }
    }

    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void) {
        guard request.hotwords == .none else { completion(.failure(error("Sherpa helper 候选不接受热词"))); return }
        sidecar.warmUp(providerID: request.descriptor.id.rawValue, modelDirectory: request.descriptor.modelDirectory) { [weak self] warmed in
            guard let self else { return }
            switch warmed {
            case .failure(let error): completion(.failure(error))
            case .success:
                sidecar.transcribe(providerID: request.descriptor.id.rawValue, audioURL: request.audioURL) { result in
                    completion(result.map { value in
                        ASREngineResult(text: value.text, engine: value.engine, loadSeconds: value.loadSeconds, inferenceSeconds: value.durationSeconds, peakRSSMB: 0)
                    })
                }
            }
        }
    }

    func cancel(runID: UUID) { sidecar.stop() }
    func unload(completion: @escaping () -> Void) { sidecar.stop(); completion() }
    private func error(_ message: String) -> NSError { NSError(domain: "com.waykingah.typewhale.sherpa-local-engine", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

final class FunASRLocalEngineAdapter: LocalASREngineRunning {
    private let sidecar: FunASRSidecar
    init(sidecar: FunASRSidecar) { self.sidecar=sidecar }
    func warmUp(_ descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload, completion: @escaping (Result<Double, Error>) -> Void) {
        let started=ProcessInfo.processInfo.systemUptime
        sidecar.warmUp(providerID:descriptor.id.rawValue,modelDirectory:descriptor.modelDirectory) { completion($0.map { _ in ProcessInfo.processInfo.systemUptime-started }) }
    }
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void) {
        let provider=request.descriptor.id.rawValue
        let words:[String]
        switch request.hotwords { case .none: words=[]; case .list(let v): words=v; case .text(let v): words=v.isEmpty ? [] : v.components(separatedBy:" "); case .context: completion(.failure(error("FunASR 收到不兼容的上下文格式"))); return }
        let started=ProcessInfo.processInfo.systemUptime
        sidecar.warmUp(providerID:provider,modelDirectory:request.descriptor.modelDirectory) { [weak self] warm in
            guard let self else { return }; switch warm { case .failure(let e): completion(.failure(e)); case .success:
                let load=ProcessInfo.processInfo.systemUptime-started
                sidecar.transcribe(providerID:provider,audioURL:request.audioURL,hotwords:words) { result in
                    completion(result.map { .init(text:$0.text,engine:$0.engine,loadSeconds:load,inferenceSeconds:$0.durationSeconds,peakRSSMB:0) })
                }
            }
        }
    }
    func cancel(runID: UUID) { sidecar.stop() }
    func unload(completion: @escaping () -> Void) { sidecar.stop(); completion() }
    private func error(_ message:String)->NSError{NSError(domain:"com.waykingah.typewhale.funasr-local-engine",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}

final class MLXLocalEngineAdapter: LocalASREngineRunning {
    private let sidecar: MLXASRSidecar
    init(sidecar: MLXASRSidecar) { self.sidecar=sidecar }
    func warmUp(_ descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload, completion: @escaping (Result<Double, Error>) -> Void) {
        guard let provider=providerID(descriptor.id) else { completion(.failure(error("未知 MLX 模型"))); return }
        let started=ProcessInfo.processInfo.systemUptime
        sidecar.warmUp(providerID:provider,modelDirectory:descriptor.modelDirectory) { completion($0.map { _ in ProcessInfo.processInfo.systemUptime-started }) }
    }
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void) {
        guard let provider=providerID(request.descriptor.id) else { completion(.failure(error("未知 MLX 模型"))); return }
        let context:String?
        switch request.hotwords { case .none: context=nil; case .context(let value): context=value; case .list,.text: completion(.failure(error("MLX 收到不兼容的热词格式"))); return }
        let started=ProcessInfo.processInfo.systemUptime
        sidecar.warmUp(providerID:provider,modelDirectory:request.descriptor.modelDirectory) { [weak self] warm in
            guard let self else { return }; switch warm { case .failure(let e): completion(.failure(e)); case .success:
                let load=ProcessInfo.processInfo.systemUptime-started
                sidecar.transcribe(providerID:provider,audioURL:request.audioURL,contextPrompt:context) { result in
                    completion(result.map { .init(text:$0.text,engine:$0.engine,loadSeconds:load,inferenceSeconds:$0.durationSeconds,peakRSSMB:0) })
                }
            }
        }
    }
    func cancel(runID: UUID) { sidecar.stop() }
    func unload(completion: @escaping () -> Void) { sidecar.stop(); completion() }
    private func providerID(_ id:ASRCandidateID)->String? { switch id { case .qwen3MLX06B:return "qwen3-asr-0.6b-mlx"; case .qwen3MLX17B:return "qwen3-asr-1.7b-mlx"; default:return nil } }
    private func error(_ message:String)->NSError{NSError(domain:"com.waykingah.typewhale.mlx-local-engine",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
