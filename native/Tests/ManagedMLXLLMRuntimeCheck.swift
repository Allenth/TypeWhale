import Foundation

@main
struct ManagedMLXLLMRuntimeCheck {
    static func main() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ManagedMLXLLMRuntimeCheck-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let workerURL = temporaryRoot.appendingPathComponent("fake_worker.py")
        try fakeWorkerSource.write(to: workerURL, atomically: true, encoding: .utf8)
        let pythonURL = URL(fileURLWithPath: "/usr/bin/python3")
        let modelDirectory = temporaryRoot.appendingPathComponent("model", isDirectory: true)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let runtime = ManagedMLXLLMRuntime(
            pythonURL: pythonURL,
            workerURL: workerURL,
            requestTimeout: 1
        )

        let warmup = try await runtime.perform(request(
            command: .warmup,
            modelDirectory: modelDirectory
        ))
        let first = try await runtime.perform(request(
            command: .rewrite,
            modelDirectory: modelDirectory,
            userPrompt: "one"
        ))
        let second = try await runtime.perform(request(
            command: .translate,
            modelDirectory: modelDirectory,
            userPrompt: "two"
        ))
        let third = try await runtime.perform(request(
            command: .rewrite,
            modelDirectory: modelDirectory,
            userPrompt: "three"
        ))
        let reusedPIDs = [warmup, first, second, third].compactMap { $0.metrics?.peakRSSBytes }
        precondition(reusedPIDs.count == 4)
        precondition(Set(reusedPIDs).count == 1, "warmup and requests must reuse one helper")

        do {
            _ = try await runtime.perform(request(
                command: .health,
                modelDirectory: modelDirectory,
                userPrompt: "mismatched-id"
            ))
            preconditionFailure("mismatched response ID must fail")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .responseIDMismatch)
        }

        let timeoutRuntime = ManagedMLXLLMRuntime(
            pythonURL: pythonURL,
            workerURL: workerURL,
            requestTimeout: 0.1
        )
        do {
            _ = try await timeoutRuntime.perform(request(
                command: .health,
                modelDirectory: modelDirectory,
                userPrompt: "sleep"
            ))
            preconditionFailure("sleep must time out")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .timedOut)
        }
        precondition(!timeoutRuntime.isRunningForTesting)

        let cancellationRuntime = ManagedMLXLLMRuntime(
            pythonURL: pythonURL,
            workerURL: workerURL,
            requestTimeout: 5
        )
        let cancellationTask = Task {
            try await cancellationRuntime.perform(request(
                command: .health,
                modelDirectory: modelDirectory,
                userPrompt: "sleep"
            ))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(cancellationRuntime.hasActiveRequest)
        do {
            _ = try await cancellationRuntime.performIfIdle(request(
                command: .health,
                modelDirectory: modelDirectory,
                userPrompt: "must-not-queue"
            ))
            preconditionFailure("idle-only request must not queue behind active work")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .busy)
        }
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            preconditionFailure("cancelled request must not succeed")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .cancelled)
        }
        precondition(!cancellationRuntime.hasActiveRequest)
        precondition(!cancellationRuntime.isRunningForTesting)

        let crashMarker = temporaryRoot.appendingPathComponent("crash-once.marker")
        let recovered = try await runtime.perform(request(
            command: .health,
            modelDirectory: modelDirectory,
            userPrompt: "crash-once:\(crashMarker.path)"
        ))
        precondition(recovered.ok)

        do {
            _ = try await runtime.perform(request(
                command: .health,
                modelDirectory: modelDirectory,
                userPrompt: "crash-always"
            ))
            preconditionFailure("a second consecutive crash must fail")
        } catch let error as ManagedLLMRuntimeError {
            precondition(error == .helperExited)
        }

        runtime.stop()
        precondition(!runtime.isRunningForTesting)
        print("ManagedMLXLLMRuntimeCheck passed")
    }

    private static func request(
        command: ManagedMLXLLMCommand,
        modelDirectory: URL,
        userPrompt: String = ""
    ) -> ManagedMLXLLMRequest {
        ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: UUID().uuidString,
            command: command,
            modelDirectory: modelDirectory.path,
            systemPrompt: "system",
            userPrompt: userPrompt,
            reasoning: .low,
            maxTokens: 64
        )
    }

    private static let fakeWorkerSource = """
    import json
    import os
    import pathlib
    import sys
    import time

    for line in sys.stdin:
        request = json.loads(line)
        prompt = request.get("user_prompt", "")
        if prompt == "sleep":
            time.sleep(2)
        if prompt == "crash-always":
            os._exit(17)
        if prompt.startswith("crash-once:"):
            marker = pathlib.Path(prompt.split(":", 1)[1])
            if not marker.exists():
                marker.write_text("crashed", encoding="utf-8")
                os._exit(18)
        response_id = "wrong-id" if prompt == "mismatched-id" else request["id"]
        response = {
            "protocol_version": 1,
            "id": response_id,
            "ok": True,
            "final_text": "pid=" + str(os.getpid()),
            "error_code": None,
            "error_message": None,
            "metrics": {
                "load_ms": 1.0,
                "ttft_ms": 2.0,
                "completion_ms": 3.0,
                "tokens_per_second": 4.0,
                "peak_rss_bytes": os.getpid(),
                "prompt_tokens": 5,
                "completion_tokens": 6
            },
            "cancelled": False
        }
        print(json.dumps(response), flush=True)
    """
}
