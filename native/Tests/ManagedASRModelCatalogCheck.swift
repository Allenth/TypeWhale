import Foundation

@main
struct ManagedASRModelCatalogCheck {
    static func main() {
        let root = URL(fileURLWithPath: "/tmp/typewhale-models", isDirectory: true)
        let managedRoot = ManagedASRModelCatalog.rootDirectory(in: root)
        precondition(managedRoot.path == "/tmp/typewhale-models")

        let asrModels = ManagedASRModelCatalog.asrModels
        precondition(asrModels.count == 2)
        precondition(asrModels.allSatisfy { $0.kind == .asr })
        precondition(asrModels.map(\.id) == ["fun-asr-nano-2512", "fsmn-vad"])
        precondition(asrModels.contains { $0.id == "fun-asr-nano-2512" && $0.role == .primary })
        precondition(asrModels.contains { $0.id == "fsmn-vad" && $0.role == .dependency })

        for id in ["fun-asr-nano-2512"] {
            guard let model = asrModels.first(where: { $0.id == id }) else {
                preconditionFailure("missing model: \(id)")
            }
            let partialRoot = root.appendingPathComponent("partial-\(id)", isDirectory: true)
            let partialDirectory = model.directory(in: partialRoot)
            try? FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
            try? Data("not-a-model".utf8).write(to: partialDirectory.appendingPathComponent("arbitrary.bin"))
            precondition(!model.isInstalled(in: partialRoot), "arbitrary files must not mark \(id) installed")
            try? FileManager.default.removeItem(at: partialRoot)
        }

        let ttsModels = ManagedASRModelCatalog.ttsModels
        precondition(ttsModels.count == 1)
        precondition(ttsModels.allSatisfy { $0.kind == .tts })
        precondition(ttsModels.contains { $0.id == "melotts-zh" && $0.role == .primary })
        if let melo = ttsModels.first {
            let partial = melo.directory(in: root)
            try? FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
            try? Data().write(to: partial.appendingPathComponent("checkpoint.pth"))
            precondition(!melo.isInstalled(in: root), "partial Melo model must not be reported as a ready voice pack")
            try? FileManager.default.removeItem(at: partial)
        }

        let models = ManagedASRModelCatalog.models
        precondition(models.count == asrModels.count + ttsModels.count)
        precondition(Set(models.map(\.id)).count == models.count)

        for model in models {
            let directory = model.directory(in: managedRoot)
            precondition(directory.path.hasPrefix(managedRoot.path + "/"))
            precondition(!directory.path.contains(".app/Contents/Resources"))
            precondition(!model.modelScopeID.isEmpty)
            precondition(!model.displayName.isEmpty)
            precondition(model.estimatedBytes > 0)
            precondition(model.relativeDirectoryName.hasPrefix(model.kind.directoryPrefix + "/"))
            precondition(!model.relativeDirectoryName.hasSuffix("/"))
        }

        print("ManagedASRModelCatalogCheck passed")
    }
}
