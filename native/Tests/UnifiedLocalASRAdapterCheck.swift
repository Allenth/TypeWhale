import Foundation
enum LaunchDiagnostics { static func mark(_ message: String) {} }

private final class FakeEngine: LocalASREngineRunning {
    let kind: ASREngineKind
    var requests: [ASREngineRequest] = []
    init(_ kind: ASREngineKind) { self.kind = kind }
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void) {
        requests.append(request)
        completion(.success(.init(text: request.descriptor.id.rawValue, engine: kind.rawValue, loadSeconds: 0.1, inferenceSeconds: 0.2, peakRSSMB: 1)))
    }
    func cancel(runID: UUID) {}
    func unload(completion: @escaping () -> Void) { completion() }
}

@main struct UnifiedLocalASRAdapterCheck {
    static func main() throws {
        let sherpa=FakeEngine(.sherpa), fun=FakeEngine(.funASR), mlx=FakeEngine(.mlx)
        let adapter=UnifiedLocalASRAdapter(engines:[.sherpa:sherpa,.funASR:fun,.mlx:mlx])
        let words=["TypeWhale","魔搭"]
        for (index,id) in ASRCandidateID.allCases.enumerated() {
            let kind:ASREngineKind = index < 2 ? .sherpa : (index == 2 ? .funASR : .mlx)
            let strategy:ASRHotwordStrategy = id == .funASRNano2512 ? .nativeList : .unsupported
            let descriptor=ASRModelDescriptor(id:id,displayName:id.rawValue,engine:kind,modelDirectory:URL(fileURLWithPath:"/tmp"),requiredRelativePaths:[],hotwordStrategy:strategy,readiness:.ready,productionReady:true)
            let result=wait { adapter.transcribe(candidate:descriptor,audioURL:URL(fileURLWithPath:"/tmp/a.wav"),hotwords:words,completion:$0) }
            guard case .success(let value)=result else { preconditionFailure("\(result)") }
            precondition(value.text==id.rawValue)
        }
        precondition(sherpa.requests.first?.hotwords == ASRHotwordPayload.none)
        precondition(fun.requests.first?.hotwords == .list(words))
        precondition(mlx.requests.first?.hotwords == .none)
        print("UnifiedLocalASRAdapterCheck passed")
    }
    static func wait<T>(_ operation:(@escaping(Result<T,Error>)->Void)->Void)->Result<T,Error>{let s=DispatchSemaphore(value:0);var r:Result<T,Error>!;operation{r=$0;s.signal()};precondition(s.wait(timeout:.now()+2) == .success);return r}
}
