import CryptoKit
import Foundation

struct ManagedLLMArtifact: Equatable {
    let name: String
    let expectedBytes: Int64
    let sha256: String
}

struct ManagedLLMModelDescriptor: Equatable {
    let id: ManagedLLMModelID
    let displayName: String
    let detailText: String
    let directoryName: String
    let repository: URL
    let revision: String
    let recommendedMemoryGB: Int
    let artifacts: [ManagedLLMArtifact]

    var totalBytes: Int64 {
        artifacts.reduce(0) { $0 + $1.expectedBytes }
    }

    func downloadURL(for artifact: ManagedLLMArtifact) -> URL {
        var components = URLComponents(
            url: repository
                .appendingPathComponent(revision)
                .appendingPathComponent(artifact.name),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        return components.url!
    }
}

enum ManagedLLMReadiness: Equatable {
    case missing
    case invalid(String)
    case ready(URL)
}

enum ManagedLLMModelCatalog {
    static let qwen3_4BInstruct2507_4bit = ManagedLLMModelDescriptor(
        id: .qwen3_4BInstruct2507_4bit,
        displayName: "本地直驱 Qwen3 4B Instruct",
        detailText: "TypeWhale 本地直驱 · 4-bit",
        directoryName: "qwen3-4b-instruct-2507-4bit",
        repository: URL(
            string: "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve"
        )!,
        revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
        recommendedMemoryGB: 8,
        artifacts: [
            ManagedLLMArtifact(
                name: ".gitattributes",
                expectedBytes: 1_570,
                sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
            ),
            ManagedLLMArtifact(
                name: "README.md",
                expectedBytes: 969,
                sha256: "7b17ce562d7ea121c86d2ffdf660eed3726ac5b52cacfa9f1de11a65969f5657"
            ),
            ManagedLLMArtifact(
                name: "added_tokens.json",
                expectedBytes: 707,
                sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"
            ),
            ManagedLLMArtifact(
                name: "chat_template.jinja",
                expectedBytes: 4_040,
                sha256: "40c21f34cf67d8c760ef72f8ad3ae5afad514299d4b06e91dd9a8d705af7b541"
            ),
            ManagedLLMArtifact(
                name: "config.json",
                expectedBytes: 938,
                sha256: "574349e5a343236546fda55e4744a76e181f534182d7dc60ff1bad7e7a502849"
            ),
            ManagedLLMArtifact(
                name: "generation_config.json",
                expectedBytes: 238,
                sha256: "835fffe355c9438e7a25be099b3fccaa98350b83451f9fd2d99512e74f1ade48"
            ),
            ManagedLLMArtifact(
                name: "merges.txt",
                expectedBytes: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
            ),
            ManagedLLMArtifact(
                name: "model.safetensors",
                expectedBytes: 2_263_022_417,
                sha256: "2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f"
            ),
            ManagedLLMArtifact(
                name: "model.safetensors.index.json",
                expectedBytes: 63_964,
                sha256: "388d811b8b7c2608dd04cce1bcb04a8bf715d19b42790894e6d3427ff429a777"
            ),
            ManagedLLMArtifact(
                name: "special_tokens_map.json",
                expectedBytes: 613,
                sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"
            ),
            ManagedLLMArtifact(
                name: "tokenizer.json",
                expectedBytes: 11_422_654,
                sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"
            ),
            ManagedLLMArtifact(
                name: "tokenizer_config.json",
                expectedBytes: 5_440,
                sha256: "4397cc477eb6d79715ccd2000accd6b3531928f30029665832fa1b255f24d2b9"
            ),
            ManagedLLMArtifact(
                name: "vocab.json",
                expectedBytes: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
            ),
        ]
    )

    static let models = [qwen3_4BInstruct2507_4bit]

    static func rootDirectory(in modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent("LLM", isDirectory: true)
    }
}

private final class ManagedLLMVerificationCache {
    private let lock = NSLock()
    private var verifiedKeys = Set<String>()

    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return verifiedKeys.contains(key)
    }

    func insert(_ key: String) {
        lock.lock()
        verifiedKeys.insert(key)
        lock.unlock()
    }
}

struct ManagedLLMModelRegistry {
    private static let verificationCache = ManagedLLMVerificationCache()

    let rootURL: URL
    let descriptors: [ManagedLLMModelDescriptor]
    private let fileManager: FileManager

    init(
        rootURL: URL,
        descriptors: [ManagedLLMModelDescriptor] = ManagedLLMModelCatalog.models,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.descriptors = descriptors
        self.fileManager = fileManager
    }

    func descriptor(for id: ManagedLLMModelID) -> ManagedLLMModelDescriptor? {
        descriptors.first { $0.id == id }
    }

    func modelDirectory(for id: ManagedLLMModelID) -> URL {
        guard let descriptor = descriptor(for: id) else {
            return rootURL.appendingPathComponent(id.rawValue, isDirectory: true)
        }
        return rootURL.appendingPathComponent(descriptor.directoryName, isDirectory: true)
    }

    func readiness(for id: ManagedLLMModelID) -> ManagedLLMReadiness {
        guard let descriptor = descriptor(for: id) else {
            return .invalid("未知的本地直驱模型")
        }
        let directory = modelDirectory(for: id)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue else {
            return .invalid("受管模型路径不是目录")
        }

        let standardizedRoot = directory.standardizedFileURL
        var cacheParts = [descriptor.revision, standardizedRoot.path]
        for artifact in descriptor.artifacts {
            let artifactURL = directory.appendingPathComponent(artifact.name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: artifactURL.path),
                  let fileType = attributes[.type] as? FileAttributeType,
                  let size = attributes[.size] as? NSNumber else {
                return .invalid("缺少模型文件：\(artifact.name)")
            }
            let resolvedURL: URL
            switch fileType {
            case .typeRegular:
                resolvedURL = artifactURL.standardizedFileURL
            case .typeSymbolicLink:
                resolvedURL = artifactURL.resolvingSymlinksInPath().standardizedFileURL
                guard isInside(resolvedURL, root: standardizedRoot) else {
                    return .invalid("模型文件超出 TypeWhale 受管目录：\(artifact.name)")
                }
                guard let resolvedAttributes = try? fileManager.attributesOfItem(atPath: resolvedURL.path),
                      (resolvedAttributes[.type] as? FileAttributeType) == .typeRegular else {
                    return .invalid("模型符号链接目标无效：\(artifact.name)")
                }
            default:
                return .invalid("模型文件类型无效：\(artifact.name)")
            }
            guard size.int64Value == artifact.expectedBytes else {
                return .invalid("模型文件大小不匹配：\(artifact.name)")
            }
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            cacheParts.append(
                "\(artifact.name):\(fileType.rawValue):\(size.int64Value):\(modified):\(resolvedURL.path)"
            )
        }

        let cacheKey = cacheParts.joined(separator: "|")
        if Self.verificationCache.contains(cacheKey) {
            return .ready(directory)
        }
        for artifact in descriptor.artifacts {
            let artifactURL = directory.appendingPathComponent(artifact.name).resolvingSymlinksInPath()
            guard (try? Self.sha256(of: artifactURL)) == artifact.sha256 else {
                return .invalid("模型文件校验失败：\(artifact.name)")
            }
        }
        Self.verificationCache.insert(cacheKey)
        return .ready(directory)
    }

    private func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
