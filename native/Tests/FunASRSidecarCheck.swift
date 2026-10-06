import Foundation

enum LaunchDiagnostics {
    static func mark(_ message: String) {}
}

@main
struct FunASRSidecarCheck {
    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let worker = root.appendingPathComponent("native/Tests/Fixtures/fake_funasr_worker.py")
        let sidecar = FunASRSidecar(
            pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
            workerURL: worker,
            requestTimeout: 2
        )

        let warmup = wait { completion in
            sidecar.warmUp(
                providerID: "fun-asr-nano-2512",
                modelDirectory: URL(fileURLWithPath: "/tmp/model"),
                completion: completion
            )
        }
        guard case .success(let engine) = warmup else { preconditionFailure("warmup failed: \(warmup)") }
        precondition(engine == "fun-asr-nano-2512/fake")

        let recognition = wait { completion in
            sidecar.transcribe(
                providerID: "fun-asr-nano-2512",
                audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                hotwords: ["Qwen3-ASR"],
                completion: completion
            )
        }
        guard case .success(let response) = recognition else { preconditionFailure("transcribe failed: \(recognition)") }
        precondition(response.text == "测试识别")
        precondition(response.engine == "fun-asr-nano-2512/fake")
        precondition(response.hotwordStrategy == "native_list")
        precondition(response.hotwordCount == 1)
        sidecar.stop()
        print("FunASRSidecarCheck passed")
    }

    private static func wait<T>(
        _ operation: (@escaping (Result<T, Error>) -> Void) -> Void
    ) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        operation {
            result = $0
            semaphore.signal()
        }
        precondition(semaphore.wait(timeout: .now() + 5) == .success)
        return result!
    }
}
