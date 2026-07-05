import Foundation

@main
struct ManagedASRModelCatalogCheck {
    static func main() {
        let root = URL(fileURLWithPath: "/tmp/typewhale-models", isDirectory: true)
        let funASRRoot = ManagedASRModelCatalog.rootDirectory(in: root)
        precondition(funASRRoot.path == "/tmp/typewhale-models/funasr")

        let models = ManagedASRModelCatalog.models
        precondition(models.count == 5)
        precondition(Set(models.map(\.id)).count == models.count)
        precondition(models.contains { $0.id == "fun-asr-nano-2512" && $0.role == .primary })
        precondition(models.contains { $0.id == "paraformer-hotword-contextual" && $0.role == .primary })
        precondition(models.contains { $0.id == "fsmn-vad" && $0.role == .dependency })

        for model in models {
            let directory = model.directory(in: funASRRoot)
            precondition(directory.path.hasPrefix(funASRRoot.path + "/"))
            precondition(!directory.path.contains(".app/Contents/Resources"))
            precondition(!model.modelScopeID.isEmpty)
            precondition(!model.displayName.isEmpty)
            precondition(model.estimatedBytes > 0)
            precondition(!model.relativeDirectoryName.contains("/"))
        }

        print("ManagedASRModelCatalogCheck passed")
    }
}
