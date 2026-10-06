import Foundation

@main
struct TTSLabRuntimeAvailabilityCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-runtime-availability-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let qwenWorker = resources.appendingPathComponent("typewhale-ttskit-worker")
        FileManager.default.createFile(atPath: qwenWorker.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: qwenWorker.path
        )

        let resolver = TTSLabRuntimeResolver(
            resourcesURL: resources,
            managedRuntimeRoot: runtimes
        )
        let availability = TTSLabRuntimeAvailability(
            resolver: resolver,
            resourcesURL: resources,
            legacyPythonURL: root.appendingPathComponent("python3")
        )
        let qwen = model(id: "qwen3-tts-06b-coreml", runtime: .ttsKit, root: root)
        precondition(availability.readiness(for: qwen) == .ready)

        try FileManager.default.removeItem(at: qwenWorker)
        precondition(availability.readiness(for: qwen) == .unavailable)

        let legacyWorker = resources.appendingPathComponent("tts_benchmark_worker.py")
        FileManager.default.createFile(atPath: legacyWorker.path, contents: Data())
        let python = root.appendingPathComponent("python3")
        FileManager.default.createFile(atPath: python.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let legacyAvailability = TTSLabRuntimeAvailability(
            resolver: resolver,
            resourcesURL: resources,
            legacyPythonURL: python
        )
        precondition(
            legacyAvailability.readiness(
                for: model(id: "sherpa-vits-melo-tts-zh_en", runtime: .sherpaONNX, root: root)
            ) == .ready
        )
        precondition(
            legacyAvailability.readiness(
                for: model(id: "unknown", runtime: .sherpaONNX, root: root)
            ) == .unavailable
        )

        print("TTSLabRuntimeAvailabilityCheck passed")
    }

    private static func model(id: String, runtime: TTSLabRuntime, root: URL) -> TTSLabModel {
        TTSLabModel(
            id: id,
            displayName: id,
            tier: 1,
            runtime: runtime,
            capabilities: .basic,
            directory: root
        )
    }
}
