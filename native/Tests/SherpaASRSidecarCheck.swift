import Foundation

@main
struct SherpaASRSidecarCheck {
    static func main() {
        let worker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("native/Tests/Fixtures/fake_sherpa_asr_worker.py")
        let sidecar = SherpaASRSidecar(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [worker.path],
            requestTimeout: 2
        )
        let warm: Result<String, Error> = wait {
            sidecar.warmUp(providerID: "qwen3-asr-0.6b-sherpa-int8", modelDirectory: URL(fileURLWithPath: "/tmp/model"), completion: $0)
        }
        guard case .success(let engine) = warm else { preconditionFailure("\(warm)") }
        precondition(engine == "qwen3-asr-0.6b-sherpa-int8/fake")
        let result: Result<SherpaASRTranscriptionResult, Error> = wait {
            sidecar.transcribe(providerID: "qwen3-asr-0.6b-sherpa-int8", audioURL: URL(fileURLWithPath: "/tmp/a.wav"), completion: $0)
        }
        guard case .success(let value) = result else { preconditionFailure("\(result)") }
        precondition(value.text == "Sherpa 隔离测试")
        sidecar.stop()

        let crashing = SherpaASRSidecar(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [worker.path],
            requestTimeout: 2
        )
        let crashWarm: Result<String, Error> = wait {
            crashing.warmUp(providerID: "crash-255", modelDirectory: URL(fileURLWithPath: "/tmp/model"), completion: $0)
        }
        guard case .success = crashWarm else { preconditionFailure("\(crashWarm)") }
        let crashed: Result<SherpaASRTranscriptionResult, Error> = wait {
            crashing.transcribe(providerID: "crash-255", audioURL: URL(fileURLWithPath: "/tmp/a.wav"), completion: $0)
        }
        guard case .failure(let error) = crashed else { preconditionFailure("worker exit must be recoverable") }
        precondition(error.localizedDescription.contains("已退出"))
        print("SherpaASRSidecarCheck passed")
    }

    static func wait<T>(_ operation: (@escaping (Result<T, Error>) -> Void) -> Void) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        operation { result = $0; semaphore.signal() }
        precondition(semaphore.wait(timeout: .now() + 5) == .success)
        return result
    }
}
