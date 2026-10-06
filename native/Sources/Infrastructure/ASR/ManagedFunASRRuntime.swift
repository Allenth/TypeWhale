import Foundation

enum FunASRRuntimeState: Equatable {
    case missing
    case invalid(String)
    case ready(URL)
}

struct ManagedFunASRRuntime {
    typealias ModuleVerifier = (URL) -> Bool

    let rootURL: URL
    private let fileManager: FileManager
    private let moduleVerifier: ModuleVerifier

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        moduleVerifier: @escaping ModuleVerifier = Self.verifyModules
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.moduleVerifier = moduleVerifier
    }

    var pythonURL: URL {
        rootURL.appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
    }

    var versionMarkerURL: URL {
        rootURL.appendingPathComponent(".typewhale-funasr-runtime-version")
    }

    var state: FunASRRuntimeState {
        guard let structuralState else { return .missing }
        if case .invalid(let message) = structuralState { return .invalid(message) }
        guard case .ready = structuralState else { return structuralState }
        guard moduleVerifier(pythonURL) else {
            return .invalid("运行环境依赖校验失败")
        }
        return .ready(pythonURL)
    }

    var structuralState: FunASRRuntimeState? {
        guard fileManager.fileExists(atPath: rootURL.path) else { return nil }
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            return .invalid("运行环境 Python 缺失")
        }
        guard let marker = try? String(contentsOf: versionMarkerURL, encoding: .utf8) else {
            return .invalid("运行环境版本标记缺失")
        }
        guard marker.trimmingCharacters(in: .whitespacesAndNewlines) == FunASRRuntimeManifest.version else {
            return .invalid("运行环境版本不匹配")
        }
        return .ready(pythonURL)
    }

    func writeVersionMarker() throws {
        try FunASRRuntimeManifest.version.write(to: versionMarkerURL, atomically: true, encoding: .utf8)
    }

    static func verifyModules(pythonURL: URL) -> Bool {
        let modules = FunASRRuntimeManifest.requiredModules
        let versions = FunASRRuntimeManifest.requiredVersions
        let script = """
        import importlib
        modules = \(pythonListLiteral(modules))
        expected = \(pythonDictionaryLiteral(versions))
        for name in modules:
            importlib.import_module(name)
        for name, version in expected.items():
            module = importlib.import_module(name)
            actual = getattr(module, "__version__", None)
            if actual is not None and str(actual) != version:
                raise SystemExit(f"{name}={actual}, expected={version}")
        """
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func pythonDictionaryLiteral(_ values: [String: String]) -> String {
        let entries = values.keys.sorted().map { key in
            "\(String(reflecting: key)): \(String(reflecting: values[key] ?? ""))"
        }
        return "{" + entries.joined(separator: ", ") + "}"
    }

    private static func pythonListLiteral(_ values: [String]) -> String {
        "[" + values.sorted().map(String.init(reflecting:)).joined(separator: ", ") + "]"
    }
}
