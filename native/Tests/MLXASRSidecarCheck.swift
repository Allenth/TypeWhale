import Foundation
@main struct MLXASRSidecarCheck {
    static func main() {
        let worker=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("native/Tests/Fixtures/fake_mlx_asr_worker.py")
        let sidecar=MLXASRSidecar(pythonURL:URL(fileURLWithPath:"/usr/bin/python3"),workerURL:worker,requestTimeout:2)
        let warm:Result<String,Error> = wait { sidecar.warmUp(providerID:"qwen3-asr-0.6b-mlx",modelDirectory:URL(fileURLWithPath:"/tmp/model"),completion:$0) }
        guard case .success(let engine)=warm else { preconditionFailure("\(warm)") }; precondition(engine=="qwen3-asr-0.6b-mlx/fake")
        let result:Result<MLXASRTranscriptionResult,Error> = wait { sidecar.transcribe(providerID:"qwen3-asr-0.6b-mlx",audioURL:URL(fileURLWithPath:"/tmp/a.wav"),contextPrompt:nil,completion:$0) }
        guard case .success(let value)=result else { preconditionFailure("\(result)") }; precondition(value.text=="MLX 测试识别")
        sidecar.stop(); print("MLXASRSidecarCheck passed")
    }
    static func wait<T>(_ operation: (@escaping (Result<T, Error>) -> Void) -> Void) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        operation { result = $0; semaphore.signal() }
        precondition(semaphore.wait(timeout: .now() + 5) == .success)
        return result
    }
}
