import Foundation

private final class FakeRecognizer: SherpaNativeRecognizing {
    let text: String
    private(set) var closeCount = 0

    init(text: String) {
        self.text = text
    }

    func transcribe(audioURL: URL) throws -> String {
        precondition(audioURL.path == "/tmp/benchmark.wav")
        return text
    }

    func close() {
        closeCount += 1
    }
}

private final class BlockingRecognizer: SherpaNativeRecognizing {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func transcribe(audioURL: URL) throws -> String {
        started.signal()
        precondition(release.wait(timeout: .now() + 2) == .success)
        return "不应交付的旧结果"
    }

    func close() {}
}

@main
struct SherpaBenchmarkAdapterCheck {
    static func main() {
        let recognizer = FakeRecognizer(text: "真实识别文本")
        var createdPayload: ASRHotwordPayload?
        let adapter = SherpaBenchmarkAdapter { descriptor, payload in
            precondition(descriptor.id == .parakeetTDT06B)
            createdPayload = payload
            return recognizer
        }
        let descriptor = ASRModelDescriptor(
            id: .parakeetTDT06B,
            displayName: "Parakeet TDT 0.6B v2 · Sherpa int8",
            engine: .sherpa,
            modelDirectory: URL(fileURLWithPath: "/tmp/qwen", isDirectory: true),
            requiredRelativePaths: [],
            hotwordStrategy: .unsupported,
            readiness: .ready,
            productionReady: true
        )
        let request = ASREngineRequest(
            runID: UUID(),
            descriptor: descriptor,
            audioURL: URL(fileURLWithPath: "/tmp/benchmark.wav"),
            hotwords: .none
        )

        let semaphore = DispatchSemaphore(value: 0)
        var delivered: Result<ASREngineResult, Error>?
        adapter.run(request: request) {
            delivered = $0
            semaphore.signal()
        }
        precondition(semaphore.wait(timeout: .now() + 2) == .success)
        guard case .success(let result) = delivered else {
            preconditionFailure("expected successful sherpa result")
        }
        precondition(result.text == "真实识别文本")
        precondition(result.engine == "parakeet-tdt-0.6b-v2-sherpa-int8/sherpa-native")
        precondition(result.loadSeconds >= 0)
        precondition(result.inferenceSeconds >= 0)
        precondition(createdPayload == .none)

        let unload = DispatchSemaphore(value: 0)
        adapter.unload { unload.signal() }
        precondition(unload.wait(timeout: .now() + 2) == .success)
        precondition(recognizer.closeCount == 1)

        let blocking = BlockingRecognizer()
        let cancellingAdapter = SherpaBenchmarkAdapter { _, _ in blocking }
        let cancelledRunID = UUID()
        let cancelledRequest = ASREngineRequest(
            runID: cancelledRunID,
            descriptor: descriptor,
            audioURL: URL(fileURLWithPath: "/tmp/benchmark.wav"),
            hotwords: .none
        )
        let cancelledCompletion = DispatchSemaphore(value: 0)
        var cancelledResult: Result<ASREngineResult, Error>?
        cancellingAdapter.run(request: cancelledRequest) {
            cancelledResult = $0
            cancelledCompletion.signal()
        }
        precondition(blocking.started.wait(timeout: .now() + 2) == .success)
        cancellingAdapter.cancel(runID: cancelledRunID)
        blocking.release.signal()
        precondition(cancelledCompletion.wait(timeout: .now() + 2) == .success)
        guard case .failure = cancelledResult else {
            preconditionFailure("cancelled run must not deliver successful text")
        }

        print("SherpaBenchmarkAdapterCheck passed")
    }
}
