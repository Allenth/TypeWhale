import Foundation

enum AppPaths {
    static let models = URL(fileURLWithPath: "/tmp/typewhale-model-manifest-check/models", isDirectory: true)
    static let resources = URL(fileURLWithPath: "/tmp/typewhale-model-manifest-check/resources", isDirectory: true)
}

@main
struct LocalSherpaModelManifestCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-parakeet-manifest-\(UUID().uuidString)", isDirectory: true)
        let zipformerRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-zipformer-manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.removeItem(at: zipformerRoot) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zipformerRoot, withIntermediateDirectories: true)

        precondition(!ParakeetTDTModelManifest.isInstalled(at: root))
        for relativePath in ParakeetTDTModelManifest.requiredFiles {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x01]).write(to: url)
        }
        precondition(ParakeetTDTModelManifest.isInstalled(at: root))
        precondition(ParakeetTDTModelManifest.requiredFiles == [
            "encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt",
        ])

        precondition(!ZipformerBilingualModelManifest.isInstalled(at: zipformerRoot))
        for relativePath in ZipformerBilingualModelManifest.requiredFiles {
            let url = zipformerRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x01]).write(to: url)
        }
        precondition(ZipformerBilingualModelManifest.isInstalled(at: zipformerRoot))
        precondition(ZipformerBilingualModelManifest.requiredFiles == [
            "encoder-epoch-99-avg-1.int8.onnx",
            "decoder-epoch-99-avg-1.onnx",
            "joiner-epoch-99-avg-1.int8.onnx",
            "tokens.txt",
        ])

        print("LocalSherpaModelManifestCheck passed")
    }
}
