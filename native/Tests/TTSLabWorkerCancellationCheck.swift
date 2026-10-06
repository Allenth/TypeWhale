import Foundation

@main
struct TTSLabWorkerCancellationCheck {
    static func main() throws {
        let workerURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let pythonURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let client = TTSLabWorkerClient(
            pythonURL: pythonURL,
            workerURL: workerURL,
            fakeDelay: 10
        )
        let model = TTSLabModel(
            id: "fake",
            displayName: "Fake",
            tier: 1,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: FileManager.default.temporaryDirectory
        )

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { finished.signal() }
            try? client.start(model: model)
            _ = try? client.prepare()
        }
        Thread.sleep(forTimeInterval: 0.2)
        let started = Date()
        client.stop()
        precondition(finished.wait(timeout: .now() + 2) == .success)
        precondition(Date().timeIntervalSince(started) < 2)
        precondition(!client.isRunning)
        print("TTSLabWorkerCancellationCheck passed")
    }
}
