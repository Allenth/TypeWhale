import Darwin
import Foundation

enum ManagedMLXRuntimeState: Equatable {
    case missing
    case invalid(String)
    case ready(URL)
}

struct ManagedMLXRuntimeProbeResult: Equatable {
    let pythonURL: URL?
    let errorCode: String?
    let userMessage: String?
    let technicalDetail: String?

    var isReady: Bool {
        pythonURL != nil && errorCode == nil
    }

    static func success(pythonURL: URL) -> ManagedMLXRuntimeProbeResult {
        ManagedMLXRuntimeProbeResult(
            pythonURL: pythonURL,
            errorCode: nil,
            userMessage: nil,
            technicalDetail: nil
        )
    }

    static func failure(
        code: String,
        userMessage: String,
        technicalDetail: String? = nil
    ) -> ManagedMLXRuntimeProbeResult {
        ManagedMLXRuntimeProbeResult(
            pythonURL: nil,
            errorCode: code,
            userMessage: userMessage,
            technicalDetail: technicalDetail
        )
    }
}

struct ManagedMLXRuntimeLocator {
    typealias ModuleVerifier = (URL) -> ManagedMLXRuntimeProbeResult

    static let requiredPackageVersions = [
        "mlx-lm": "0.30.5",
        "transformers": "5.0.0rc3",
    ]

    let runtimesRootURL: URL
    private let fileManager: FileManager
    private let moduleVerifier: ModuleVerifier

    init(
        runtimesRootURL: URL,
        fileManager: FileManager = .default,
        moduleVerifier: @escaping ModuleVerifier = Self.verifyModules
    ) {
        self.runtimesRootURL = runtimesRootURL
        self.fileManager = fileManager
        self.moduleVerifier = moduleVerifier
    }

    static func candidateRoots(in runtimesRootURL: URL) -> [URL] {
        [
            runtimesRootURL.appendingPathComponent("mlx-llm/v1", isDirectory: true),
            runtimesRootURL.appendingPathComponent("mlx-asr/v1", isDirectory: true),
        ]
    }

    var state: ManagedMLXRuntimeState {
        var firstStructuralFailure: String?
        for rootURL in Self.candidateRoots(in: runtimesRootURL) {
            guard fileManager.fileExists(atPath: rootURL.path) else { continue }
            guard let pythonURL = executablePython(in: rootURL) else {
                firstStructuralFailure = firstStructuralFailure ?? "运行环境 Python 缺失"
                continue
            }
            return .ready(pythonURL)
        }
        if let firstStructuralFailure {
            return .invalid(firstStructuralFailure)
        }
        return .missing
    }

    func probe() -> ManagedMLXRuntimeProbeResult {
        var firstStructuralFailure: ManagedMLXRuntimeProbeResult?

        for rootURL in Self.candidateRoots(in: runtimesRootURL) {
            guard fileManager.fileExists(atPath: rootURL.path) else { continue }
            guard let pythonURL = executablePython(in: rootURL) else {
                firstStructuralFailure = firstStructuralFailure ?? .failure(
                    code: "runtime_python_missing",
                    userMessage: "运行环境 Python 缺失"
                )
                continue
            }
            let verification = moduleVerifier(pythonURL)
            guard verification.isReady else { return verification }
            return .success(pythonURL: pythonURL)
        }

        if let firstStructuralFailure {
            return firstStructuralFailure
        }
        return .failure(
            code: "runtime_missing",
            userMessage: "TypeWhale 本地运行环境尚未安装"
        )
    }

    private func executablePython(in rootURL: URL) -> URL? {
        let binURL = rootURL.appendingPathComponent("python/bin", isDirectory: true)
        for name in ["python3", "python3.10"] {
            let candidate = binURL.appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func verifyModules(pythonURL: URL) -> ManagedMLXRuntimeProbeResult {
        verifyModules(pythonURL: pythonURL, timeout: 15)
    }

    static func verifyModules(
        pythonURL: URL,
        timeout: TimeInterval
    ) -> ManagedMLXRuntimeProbeResult {
        let process = Process()
        let errorPipe = Pipe()
        let output = BoundedProcessOutput(maximumBytes: 8_192)
        let termination = DispatchSemaphore(value: 0)
        process.executableURL = pythonURL
        process.arguments = [
            "-c",
            """
            import importlib.metadata
            import sys
            required = {"mlx-lm": "0.30.5", "transformers": "5.0.0rc3"}
            for package, version in required.items():
                try:
                    actual = importlib.metadata.version(package)
                except Exception as error:
                    print(f"{package} metadata unavailable: {error}", file=sys.stderr)
                    raise SystemExit(42)
                if actual != version:
                    print(f"{package} expected {version}, found {actual}", file=sys.stderr)
                    raise SystemExit(41)
            import mlx_lm
            """,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        process.terminationHandler = { _ in
            termination.signal()
        }

        do {
            try process.run()
            guard termination.wait(timeout: .now() + max(0.01, timeout)) == .success else {
                terminate(process, completion: termination)
                errorPipe.fileHandleForReading.readabilityHandler = nil
                output.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                return .failure(
                    code: "runtime_probe_timeout",
                    userMessage: "运行环境导入检查超时",
                    technicalDetail: sanitizedTechnicalDetail(output.data)
                )
            }
            errorPipe.fileHandleForReading.readabilityHandler = nil
            output.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            let detail = sanitizedTechnicalDetail(output.data)
            guard process.terminationReason == .exit else {
                return .failure(
                    code: "runtime_import_failed",
                    userMessage: "运行环境依赖无法加载",
                    technicalDetail: detail
                )
            }
            switch process.terminationStatus {
            case 0:
                return .success(pythonURL: pythonURL)
            case 41:
                return .failure(
                    code: "runtime_version_mismatch",
                    userMessage: "运行环境依赖版本不匹配",
                    technicalDetail: detail
                )
            case 42:
                return .failure(
                    code: "runtime_dependency_missing",
                    userMessage: "运行环境依赖缺失",
                    technicalDetail: detail
                )
            default:
                return .failure(
                    code: "runtime_import_failed",
                    userMessage: importFailureMessage(for: detail),
                    technicalDetail: detail
                )
            }
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return .failure(
                code: "runtime_probe_launch_failed",
                userMessage: "运行环境 Python 无法启动",
                technicalDetail: sanitizedTechnicalDetail(
                    Data(error.localizedDescription.utf8)
                )
            )
        }
    }

    private static func terminate(
        _ process: Process,
        completion: DispatchSemaphore
    ) {
        if process.isRunning {
            process.terminate()
        }
        guard completion.wait(timeout: .now() + 0.5) != .success,
              process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        _ = completion.wait(timeout: .now() + 0.5)
    }

    private static func importFailureMessage(for technicalDetail: String?) -> String {
        let lowercased = technicalDetail?.lowercased() ?? ""
        let incompatibilityMarkers = [
            "dlopen",
            "library not loaded",
            "malformed",
            "__thread_bss",
            "mach-o",
            "incompatible architecture",
        ]
        if incompatibilityMarkers.contains(where: lowercased.contains) {
            return "运行环境与当前 macOS 不兼容"
        }
        return "运行环境依赖无法加载"
    }

    private static func sanitizedTechnicalDetail(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let raw = String(decoding: data.prefix(8_192), as: UTF8.self)
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let allowed = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar.value >= 0x20
        }
        let sanitized = String(String.UnicodeScalarView(allowed))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var storage = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < maximumBytes else { return }
        storage.append(data.prefix(maximumBytes - storage.count))
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
