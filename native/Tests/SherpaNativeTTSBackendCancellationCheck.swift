import Foundation

@main
struct SherpaNativeTTSBackendCancellationCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("slow-sherpa-onnx-offline-tts")
        let started = root.appendingPathComponent("started")
        let script = """
        #!/usr/bin/env bash
        touch "\(started.path)"
        exec sleep 10
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let packDirectory = root.appendingPathComponent("pack", isDirectory: true)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        let request = OpenClawVoiceSynthesisRequest(
            text: "取消测试。",
            settings: .default,
            workerScriptURL: nil,
            modelsRoot: root,
            outputURL: root.appendingPathComponent("output.wav")
        )
        let backend = SherpaNativeTTSBackend(executableURL: executable, packDirectory: packDirectory)
        try backend.start(timeoutSeconds: 1)

        let completed = DispatchSemaphore(value: 0)
        let startedAt = Date()
        var synthesisError: Error?
        DispatchQueue.global().async {
            do {
                try backend.synthesize(request, timeoutSeconds: 30)
            } catch {
                synthesisError = error
            }
            completed.signal()
        }

        let startupDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: started.path), Date() < startupDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        precondition(FileManager.default.fileExists(atPath: started.path), "fake native process did not start")

        backend.stop()
        precondition(completed.wait(timeout: .now() + 2) == .success, "native synthesis should stop promptly")
        precondition(synthesisError != nil, "cancellation should surface as synthesis failure")
        precondition(Date().timeIntervalSince(startedAt) < 2.5, "cancellation must not wait for the synthesis timeout")
        precondition(!backend.isRunning)

        print("SherpaNativeTTSBackendCancellationCheck passed")
    }
}
