import Foundation

@main
struct TTSLabModelCatalogCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("typewhale-tts-catalog-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try makeModel(
            root: root,
            id: "zipvoice-distill-int8-zh-en-emilia",
            displayName: "ZipVoice",
            tier: 1,
            status: "passed"
        )
        try makeModel(root: root, id: "passed-b", displayName: "B Model", tier: 1, status: "passed")
        try makeModel(root: root, id: "tier-two", displayName: "Tier Two", tier: 2, status: "passed")
        try makeModel(root: root, id: "failed", displayName: "Failed", tier: 1, status: "failed")

        let malformed = root.appendingPathComponent("malformed", isDirectory: true)
        try fileManager.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: malformed.appendingPathComponent("typewhale-model.json"))

        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("typewhale-tts-outside-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outside) }
        try makeModel(root: outside, id: "escaped", displayName: "Escaped", tier: 1, status: "passed")
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("escaped"),
            withDestinationURL: outside.appendingPathComponent("escaped")
        )

        let installed = try TTSLabModelCatalog.installedModels(root: root)
        precondition(installed.map(\.id) == ["zipvoice-distill-int8-zh-en-emilia"])
        let models = try TTSLabModelCatalog.qualifiedModels(root: root)
        precondition(models.map(\.id) == ["zipvoice-distill-int8-zh-en-emilia"])
        precondition(models.allSatisfy { $0.directory.path.hasPrefix(root.path) })
        print("TTSLabModelCatalogCheck passed")
    }

    private static func makeModel(
        root: URL,
        id: String,
        displayName: String,
        tier: Int,
        status: String,
        defaultSpeakerID: Int? = nil
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("license".utf8).write(to: directory.appendingPathComponent("LICENSE"))
        try Data("model".utf8).write(to: directory.appendingPathComponent("model.bin"))
        var manifest: [String: Any] = [
            "id": id,
            "displayName": displayName,
            "tier": tier,
            "runtime": "sherpa-onnx",
            "license": "test-only",
            "licensePath": "LICENSE",
            "requiredPaths": ["model.bin", "LICENSE"],
            "qualification": ["status": status],
        ]
        manifest["defaultSpeakerID"] = defaultSpeakerID
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: directory.appendingPathComponent("typewhale-model.json"))
    }
}
