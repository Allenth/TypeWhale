import Foundation

enum MLXASRRuntimeState: Equatable { case missing, invalid(String), ready(URL) }

struct ManagedMLXASRRuntime {
    typealias ModuleVerifier = (URL) -> Bool
    let rootURL: URL
    private let fileManager: FileManager
    private let moduleVerifier: ModuleVerifier

    init(rootURL: URL, fileManager: FileManager = .default, moduleVerifier: @escaping ModuleVerifier = Self.verifyModules) {
        self.rootURL = rootURL; self.fileManager = fileManager; self.moduleVerifier = moduleVerifier
    }
    var pythonURL: URL { rootURL.appendingPathComponent("python/bin/python3") }
    var versionMarkerURL: URL { rootURL.appendingPathComponent(".typewhale-mlx-asr-runtime-version") }
    var state: MLXASRRuntimeState {
        guard case .ready = structuralState else { return structuralState }
        guard moduleVerifier(pythonURL) else { return .invalid("运行环境依赖校验失败") }
        return .ready(pythonURL)
    }
    var structuralState: MLXASRRuntimeState {
        guard fileManager.fileExists(atPath: rootURL.path) else { return .missing }
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else { return .invalid("运行环境 Python 缺失") }
        guard let marker = try? String(contentsOf: versionMarkerURL, encoding: .utf8) else { return .invalid("运行环境版本标记缺失") }
        guard marker.trimmingCharacters(in: .whitespacesAndNewlines) == MLXASRRuntimeManifest.version else { return .invalid("运行环境版本不匹配") }
        return .ready(pythonURL)
    }
    func writeVersionMarker() throws { try MLXASRRuntimeManifest.version.write(to: versionMarkerURL, atomically: true, encoding: .utf8) }
    static func verifyModules(pythonURL: URL) -> Bool {
        let expected = MLXASRRuntimeManifest.requiredVersions
        let pairs = expected.keys.sorted().map { "\(String(reflecting: $0)): \(String(reflecting: expected[$0]!))" }.joined(separator: ",")
        let script = """
        import importlib, importlib.metadata
        expected={\(pairs)}
        distributions={'mlx_audio':'mlx-audio','mlx_whisper':'mlx-whisper'}
        for name, version in expected.items():
            importlib.import_module(name)
            actual=importlib.metadata.version(distributions.get(name,name))
            assert actual == version, f'{name}={actual}, expected={version}'
        """
        let process = Process(); process.executableURL = pythonURL; process.arguments = ["-c", script]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
    }
}
