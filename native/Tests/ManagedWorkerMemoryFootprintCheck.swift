import Foundation

@main
struct ManagedWorkerMemoryFootprintCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ManagedWorkerMemoryFootprintCheck-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let worker = root.appendingPathComponent("worker.py")
        try workerSource.write(to: worker, atomically: true, encoding: .utf8)
        let runtime = ManagedMLXLLMRuntime(
            pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
            workerURL: worker,
            requestTimeout: 2
        )
        let request = ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: UUID().uuidString,
            command: .health,
            modelDirectory: root.path,
            systemPrompt: "",
            userPrompt: "",
            reasoning: .low,
            maxTokens: 1
        )

        _ = try await runtime.perform(request)
        guard let pid = runtime.ownedProcessIdentifier else {
            preconditionFailure("owned worker PID must be visible")
        }
        let workerBytes = MemoryMonitor.footprintBytes(processID: pid)
        precondition(workerBytes > 0)
        let combinedMB = MemoryMonitor.combinedFootprintMB(
            additionalProcessID: pid
        )
        precondition(
            combinedMB >= MemoryMonitor.currentFootprintMB
                + Int(workerBytes / UInt64(1024 * 1024))
        )
        precondition(MemoryMonitor.peakCombinedFootprintMB >= combinedMB)

        runtime.stop()
        precondition(runtime.ownedProcessIdentifier == nil)
        print("ManagedWorkerMemoryFootprintCheck passed")
    }

    private static let workerSource = """
    import json
    import os
    import sys

    for line in sys.stdin:
        request = json.loads(line)
        print(json.dumps({
            "protocol_version": 1,
            "id": request["id"],
            "ok": True,
            "final_text": None,
            "error_code": None,
            "error_message": None,
            "metrics": None,
            "cancelled": False
        }), flush=True)
    """
}
