import Foundation

@main
struct ASRModelRegistryCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-asr-registry-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let descriptors = ASRModelRegistry(environment: .fixture(root: root)).descriptors()
        precondition(descriptors.count == 5)
        precondition(Set(descriptors.map(\.id)) == Set(ASRCandidateID.allCases))
        precondition(descriptors.first { $0.id == .parakeetTDT06B }?.engine == .sherpa)
        precondition(descriptors.first { $0.id == .funASRNano2512 }?.hotwordStrategy == .nativeList)
        precondition(descriptors.first { $0.id == .qwen3MLX17B }?.engine == .mlx)

        let repository = root.appendingPathComponent(
            "huggingface/models--mlx-community--Qwen3-ASR-0.6B-8bit", isDirectory: true
        )
        let snapshot = repository.appendingPathComponent("snapshots/revision", isDirectory: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try "revision".write(to: repository.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        for (index, path) in [
            "config.json", "model.safetensors", "preprocessor_config.json",
            "tokenizer_config.json", "vocab.json", "merges.txt",
        ].enumerated() {
            let blob = repository.appendingPathComponent("blobs/blob-\(index)")
            try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: blob)
            let link = snapshot.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../../blobs/blob-\(index)")
        }
        let linked = ASRModelRegistry(environment: .fixture(root: root)).descriptor(for: .qwen3MLX06B)
        precondition(linked?.readiness == .ready)
        print("ASRModelRegistryCheck passed")
    }
}
