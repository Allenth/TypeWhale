import Foundation

protocol LocalASREngineRunning: AnyObject {
    func warmUp(_ descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload, completion: @escaping (Result<Double, Error>) -> Void)
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void)
    func cancel(runID: UUID)
    func unload(completion: @escaping () -> Void)
}
extension LocalASREngineRunning {
    func warmUp(_ descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload, completion: @escaping (Result<Double, Error>) -> Void) { completion(.success(0)) }
}

protocol LocalASRRunning: AnyObject {
    func probe(_ descriptor: ASRModelDescriptor) -> ASRReadiness
    func warmUp(candidate: ASRModelDescriptor, hotwords: [String], completion: @escaping (Result<Double, Error>) -> Void)
    func transcribe(candidate: ASRModelDescriptor, audioURL: URL, hotwords: [String], completion: @escaping (Result<ASREngineResult, Error>) -> Void)
    func cancel(runID: UUID)
    func unload(completion: @escaping () -> Void)
}

final class UnifiedLocalASRAdapter: LocalASRRunning {
    private let engines: [ASREngineKind: LocalASREngineRunning]
    private let lock = NSLock()
    private var activeRunID: UUID?
    private var activeEngine: LocalASREngineRunning?

    init(engines: [ASREngineKind: LocalASREngineRunning]) { self.engines = engines }
    func probe(_ descriptor: ASRModelDescriptor) -> ASRReadiness {
        guard engines[descriptor.engine] != nil else { return .unavailable("识别运行引擎不可用") }
        return descriptor.readiness
    }
    func warmUp(candidate: ASRModelDescriptor, hotwords: [String], completion: @escaping (Result<Double, Error>) -> Void) {
        guard probe(candidate) == .ready, let engine=engines[candidate.engine] else { completion(.failure(error("模型尚未就绪：\(candidate.displayName)"))); return }
        do { engine.warmUp(candidate,hotwords:try ASRHotwordEncoder.encode(words:hotwords,strategy:candidate.hotwordStrategy),completion:completion) }
        catch { completion(.failure(error)) }
    }
    func transcribe(candidate: ASRModelDescriptor, audioURL: URL, hotwords: [String], completion: @escaping (Result<ASREngineResult, Error>) -> Void) {
        guard probe(candidate) == .ready, let engine=engines[candidate.engine] else {
            completion(.failure(error("模型尚未就绪：\(candidate.displayName)"))); return
        }
        do {
            let payload=try ASRHotwordEncoder.encode(words:hotwords, strategy:candidate.hotwordStrategy)
            let runID=UUID(); lock.lock(); activeRunID=runID; activeEngine=engine; lock.unlock()
            engine.transcribe(.init(runID:runID,descriptor:candidate,audioURL:audioURL,hotwords:payload)) { [weak self] result in
                self?.lock.lock(); if self?.activeRunID == runID { self?.activeRunID=nil; self?.activeEngine=nil }; self?.lock.unlock()
                completion(result)
            }
        } catch { completion(.failure(error)) }
    }
    func cancel(runID: UUID) { lock.lock(); let engine=activeRunID == runID ? activeEngine:nil; lock.unlock(); engine?.cancel(runID:runID) }
    func unload(completion: @escaping () -> Void) { lock.lock(); let engine=activeEngine; activeRunID=nil; activeEngine=nil; lock.unlock(); engine?.unload(completion:completion) ?? completion() }
    private func error(_ message:String)->NSError{NSError(domain:"com.waykingah.typewhale.unified-local-asr",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
