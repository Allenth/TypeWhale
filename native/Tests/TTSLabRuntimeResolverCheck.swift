import Foundation

@main
struct TTSLabRuntimeResolverCheck {
    static func main() throws {
        let resources = URL(fileURLWithPath: "/Applications/Test.app/Contents/Resources")
        let runtimeRoot = URL(fileURLWithPath: "/tmp/typewhale-tts-runtimes")
        let resolver = TTSLabRuntimeResolver(
            resourcesURL: resources,
            managedRuntimeRoot: runtimeRoot
        )
        let directory = URL(fileURLWithPath: "/tmp/zipvoice")
        let zipVoice = TTSLabModel(
            id: "zipvoice-distill-int8-zh-en-emilia",
            displayName: "ZipVoice",
            tier: 1,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: directory
        )

        let descriptor = try resolver.resolve(model: zipVoice)
        precondition(descriptor.adapterID == "sherpa-zipvoice")
        precondition(descriptor.executableURL.path == "/usr/local/bin/python3")
        precondition(descriptor.arguments == [
            resources.appendingPathComponent("tts_benchmark_worker.py").path,
            "--engine", "sherpa-zipvoice",
            "--pack", directory.path,
        ])
        precondition(descriptor.environment["HF_HUB_OFFLINE"] == "1")
        precondition(descriptor.environment["TRANSFORMERS_OFFLINE"] == "1")
        precondition(descriptor.fingerprint == "zipvoice-distill-int8-reference-voices-v2")

        let unsupported = TTSLabModel(
            id: "unknown-model",
            displayName: "Unknown",
            tier: 2,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: URL(fileURLWithPath: "/tmp/unknown")
        )
        do {
            _ = try resolver.resolve(model: unsupported)
            preconditionFailure("unknown model must not resolve")
        } catch TTSLabRuntimeResolverError.unsupportedModel(let id) {
            precondition(id == "unknown-model")
        }

        print("TTSLabRuntimeResolverCheck passed")
    }
}
