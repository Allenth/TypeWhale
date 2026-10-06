import Foundation

struct ASRModelRegistry {
    struct Environment {
        let bundledModelsURL: URL
        let managedModelsURL: URL
        let legacyModelsURL: URL
        let huggingFaceHubURL: URL
        let modelScopeHubURL: URL
        let admissionEvidenceURL: URL?

        init(bundledModelsURL:URL,managedModelsURL:URL,legacyModelsURL:URL,huggingFaceHubURL:URL,modelScopeHubURL:URL,admissionEvidenceURL:URL? = nil){self.bundledModelsURL=bundledModelsURL;self.managedModelsURL=managedModelsURL;self.legacyModelsURL=legacyModelsURL;self.huggingFaceHubURL=huggingFaceHubURL;self.modelScopeHubURL=modelScopeHubURL;self.admissionEvidenceURL=admissionEvidenceURL}

        static func fixture(root: URL) -> Environment {
            Environment(
                bundledModelsURL: root.appendingPathComponent("bundled", isDirectory: true),
                managedModelsURL: root.appendingPathComponent("managed", isDirectory: true),
                legacyModelsURL: root.appendingPathComponent("legacy", isDirectory: true),
                huggingFaceHubURL: root.appendingPathComponent("huggingface", isDirectory: true),
                modelScopeHubURL: root.appendingPathComponent("modelscope", isDirectory: true),
                admissionEvidenceURL: nil
            )
        }
    }

    private struct Manifest {
        let id: ASRCandidateID
        let displayName: String
        let engine: ASREngineKind
        let directory: (Environment) -> URL
        let fallbackDirectories: (Environment) -> [URL]
        let requiredPaths: [String]
        let hotwordStrategy: ASRHotwordStrategy

        init(
            id: ASRCandidateID,
            displayName: String,
            engine: ASREngineKind,
            directory: @escaping (Environment) -> URL,
            fallbackDirectories: @escaping (Environment) -> [URL] = { _ in [] },
            requiredPaths: [String],
            hotwordStrategy: ASRHotwordStrategy
        ) {
            self.id = id
            self.displayName = displayName
            self.engine = engine
            self.directory = directory
            self.fallbackDirectories = fallbackDirectories
            self.requiredPaths = requiredPaths
            self.hotwordStrategy = hotwordStrategy
        }
    }

    let environment: Environment
    private let fileManager: FileManager

    init(environment: Environment, fileManager: FileManager = .default) {
        self.environment = environment
        self.fileManager = fileManager
    }

    func descriptors() -> [ASRModelDescriptor] {
        let admitted = admittedCandidateIDs()
        return manifests.map { manifest in
            let candidates = [manifest.directory(environment)] + manifest.fallbackDirectories(environment)
            let directory = candidates.first {
                validate(directory: $0, requiredPaths: manifest.requiredPaths) == .ready
            } ?? candidates[0]
            let readiness = validate(directory: directory, requiredPaths: manifest.requiredPaths)
            return ASRModelDescriptor(
                id: manifest.id,
                displayName: manifest.displayName,
                engine: manifest.engine,
                modelDirectory: directory,
                requiredRelativePaths: manifest.requiredPaths,
                hotwordStrategy: manifest.hotwordStrategy,
                readiness: readiness,
                productionReady: readiness == .ready && admitted.contains(manifest.id)
            )
        }
    }

    private func admittedCandidateIDs() -> Set<ASRCandidateID> {
        guard let url=environment.admissionEvidenceURL else{return Set(ASRCandidateID.allCases)}
        struct File:Decodable{let candidates:[Entry]};struct Entry:Decodable{let candidateID:ASRCandidateID;let admitted:Bool;enum CodingKeys:String,CodingKey{case candidateID="candidate_id",admitted}}
        guard let data=try? Data(contentsOf:url),let file=try? JSONDecoder().decode(File.self,from:data) else{return []}
        return Set(file.candidates.filter(\.admitted).map(\.candidateID))
    }

    func descriptor(for id: ASRCandidateID) -> ASRModelDescriptor? {
        descriptors().first { $0.id == id }
    }

    private func validate(directory: URL, requiredPaths: [String]) -> ASRReadiness {
        for relativePath in requiredPaths {
            let url = directory.appendingPathComponent(relativePath)
            guard isAllowedNonemptyModelFile(url, under: directory) else {
                return .unavailable("缺少模型文件：\(relativePath)")
            }
        }
        return .ready
    }

    private func isAllowedNonemptyModelFile(_ url: URL, under directory: URL) -> Bool {
        guard let sourceAttributes = try? fileManager.attributesOfItem(atPath: url.path),
              let sourceType = sourceAttributes[.type] as? FileAttributeType else {
            return false
        }
        if sourceType == .typeRegular {
            return (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0 > 0
        }
        guard sourceType == .typeSymbolicLink else { return false }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let allowedRoot = allowedSymlinkRoot(for: directory).standardizedFileURL
        let allowedPath = allowedRoot.path.hasSuffix("/") ? allowedRoot.path : allowedRoot.path + "/"
        guard resolvedURL.path == allowedRoot.path || resolvedURL.path.hasPrefix(allowedPath),
              let targetAttributes = try? fileManager.attributesOfItem(atPath: resolvedURL.path),
              (targetAttributes[.type] as? FileAttributeType) == .typeRegular,
              let targetSize = targetAttributes[.size] as? NSNumber,
              targetSize.int64Value > 0 else {
            return false
        }
        return true
    }

    private func allowedSymlinkRoot(for directory: URL) -> URL {
        let components = directory.standardizedFileURL.pathComponents
        guard let snapshotsIndex = components.lastIndex(of: "snapshots"), snapshotsIndex > 0 else {
            return directory
        }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(snapshotsIndex))))
    }

    private var manifests: [Manifest] {
        [
            Manifest(
                id: .senseVoiceInt8,
                displayName: "SenseVoice int8",
                engine: .sherpa,
                directory: { $0.bundledModelsURL.appendingPathComponent("sensevoice-native", isDirectory: true) },
                fallbackDirectories: {
                    [$0.managedModelsURL.appendingPathComponent("sensevoice-native", isDirectory: true)]
                },
                requiredPaths: ["model.onnx", "tokens.txt"],
                hotwordStrategy: .unsupported
            ),
            Manifest(
                id: .parakeetTDT06B,
                displayName: "Parakeet TDT 0.6B v2 · Sherpa int8",
                engine: .sherpa,
                directory: {
                    $0.managedModelsURL
                        .appendingPathComponent("parakeet-tdt-0.6b-v2-int8", isDirectory: true)
                        .appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8", isDirectory: true)
                },
                fallbackDirectories: {
                    [
                        $0.legacyModelsURL
                            .appendingPathComponent("parakeet-tdt-0.6b-v2-int8", isDirectory: true)
                            .appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8", isDirectory: true),
                    ]
                },
                requiredPaths: ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"],
                hotwordStrategy: .unsupported
            ),
            Manifest(
                id: .funASRNano2512,
                displayName: "Fun-ASR Nano 2512",
                engine: .funASR,
                directory: { $0.managedModelsURL.appendingPathComponent("funasr/fun-asr-nano-2512", isDirectory: true) },
                requiredPaths: [
                    "model.pt", "config.yaml", "multilingual.tiktoken",
                    "Qwen3-0.6B/config.json", "Qwen3-0.6B/tokenizer.json",
                ],
                hotwordStrategy: .nativeList
            ),
            Manifest(
                id: .qwen3MLX06B,
                displayName: "Qwen3-ASR 0.6B · MLX 8-bit",
                engine: .mlx,
                directory: { huggingFaceSnapshot(named: "models--mlx-community--Qwen3-ASR-0.6B-8bit", in: $0.huggingFaceHubURL) },
                requiredPaths: [
                    "config.json", "model.safetensors", "preprocessor_config.json",
                    "tokenizer_config.json", "vocab.json", "merges.txt",
                ],
                hotwordStrategy: .unsupported
            ),
            Manifest(
                id: .qwen3MLX17B,
                displayName: "Qwen3-ASR 1.7B · MLX 8-bit",
                engine: .mlx,
                directory: { huggingFaceSnapshot(named: "models--mlx-community--Qwen3-ASR-1.7B-8bit", in: $0.huggingFaceHubURL) },
                requiredPaths: [
                    "config.json", "model.safetensors", "preprocessor_config.json",
                    "tokenizer_config.json", "vocab.json", "merges.txt",
                ],
                hotwordStrategy: .unsupported
            ),
        ]
    }
}

private func huggingFaceSnapshot(named repositoryDirectoryName: String, in hubURL: URL) -> URL {
    let repository = hubURL.appendingPathComponent(repositoryDirectoryName, isDirectory: true)
    let reference = repository.appendingPathComponent("refs/main")
    if let revision = try? String(contentsOf: reference, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       !revision.isEmpty {
        return repository.appendingPathComponent("snapshots/\(revision)", isDirectory: true)
    }
    return repository.appendingPathComponent("snapshots/missing", isDirectory: true)
}
