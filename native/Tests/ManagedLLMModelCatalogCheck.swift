import CryptoKit
import Foundation

@main
struct ManagedLLMModelCatalogCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-managed-llm-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let first = Data("fixture-a".utf8)
        let second = Data("fixture-b".utf8)
        let descriptor = ManagedLLMModelDescriptor(
            id: .qwen3_4BInstruct2507_4bit,
            displayName: "Fixture Qwen",
            detailText: "Fixture",
            directoryName: "fixture-qwen",
            repository: URL(string: "https://example.invalid/model")!,
            revision: "fixture-revision",
            recommendedMemoryGB: 24,
            artifacts: [
                ManagedLLMArtifact(
                    name: "config.json",
                    expectedBytes: Int64(first.count),
                    sha256: sha256(first)
                ),
                ManagedLLMArtifact(
                    name: "model.safetensors",
                    expectedBytes: Int64(second.count),
                    sha256: sha256(second)
                ),
            ]
        )
        let registry = ManagedLLMModelRegistry(rootURL: root, descriptors: [descriptor])

        precondition(registry.readiness(for: .qwen3_4BInstruct2507_4bit) == .missing)

        let modelURL = registry.modelDirectory(for: .qwen3_4BInstruct2507_4bit)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        try Data("wrong".utf8).write(to: modelURL.appendingPathComponent("config.json"))
        if case .invalid(let message) = registry.readiness(for: .qwen3_4BInstruct2507_4bit) {
            precondition(message.contains("config.json"))
        } else {
            preconditionFailure("wrong artifact size must be rejected")
        }

        try first.write(to: modelURL.appendingPathComponent("config.json"))
        try second.write(to: modelURL.appendingPathComponent("model.safetensors"))
        precondition(registry.readiness(for: .qwen3_4BInstruct2507_4bit) == .ready(modelURL))

        try FileManager.default.removeItem(at: modelURL.appendingPathComponent("model.safetensors"))
        let outside = root.appendingPathComponent("outside")
        try second.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: modelURL.appendingPathComponent("model.safetensors"),
            withDestinationURL: outside
        )
        if case .invalid(let message) = registry.readiness(for: .qwen3_4BInstruct2507_4bit) {
            precondition(message.contains("受管目录"))
        } else {
            preconditionFailure("symlink escaping managed directory must be rejected")
        }

        let production = ManagedLLMModelCatalog.qwen3_4BInstruct2507_4bit
        precondition(production.revision == "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b")
        precondition(production.directoryName == "qwen3-4b-instruct-2507-4bit")
        precondition(production.artifacts.count == 13)
        precondition(production.totalBytes == 2_278_972_236)
        precondition(
            production.artifacts.first { $0.name == "model.safetensors" }?.sha256
                == "2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f"
        )
        precondition(
            production.downloadURL(for: production.artifacts[7]).absoluteString.contains(production.revision)
        )
        precondition(!production.downloadURL(for: production.artifacts[7]).absoluteString.contains("lmstudio"))

        print("ManagedLLMModelCatalogCheck passed")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
