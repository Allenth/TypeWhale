import CryptoKit
import Foundation

@MainActor
final class MLXASRRuntimeInstaller {
    enum State: Equatable { case missing, installing(String), ready, failed(String) }
    private let runtimeRoot: URL
    private let requirementsURL: URL
    private let fileManager: FileManager
    private var task: Task<Void, Never>?
    private(set) var state: State = .missing { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?

    init(runtimeRoot: URL, requirementsURL: URL, fileManager: FileManager = .default) {
        self.runtimeRoot = runtimeRoot; self.requirementsURL = requirementsURL; self.fileManager = fileManager
        refresh()
    }
    deinit { task?.cancel() }
    func refresh() {
        state = { if case .ready = ManagedMLXASRRuntime(rootURL: runtimeRoot, fileManager: fileManager).state { return .ready }; return .missing }()
    }
    func install() {
        guard task == nil else { return }
        state = .installing("正在安装 MLX 语音运行环境")
        let root = runtimeRoot, requirements = requirementsURL, fm = fileManager
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .utility) { try Self.performInstallation(runtimeRoot: root, requirementsURL: requirements, fileManager: fm) }.value
                task = nil; state = .ready
            } catch is CancellationError { task = nil; refresh() }
            catch { task = nil; state = .failed(error.localizedDescription) }
        }
    }
    func cancel() { task?.cancel(); task = nil; refresh() }

    nonisolated static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    nonisolated static func requirementsAreValid(_ data: Data) -> Bool { sha256(data) == MLXASRRuntimeManifest.requirementsSHA256 }
    nonisolated static func pipInstallArguments(requirementsURL: URL, cacheURL: URL) -> [String] {
        ["-m", "pip", "install", "--require-hashes", "--disable-pip-version-check", "--no-input", "--no-user", "--retries", "10", "--resume-retries", "10", "--timeout", "120", "--cache-dir", cacheURL.path, "-r", requirementsURL.path]
    }

    private nonisolated static func performInstallation(runtimeRoot: URL, requirementsURL: URL, fileManager: FileManager) throws {
        guard let requirementsData = try? Data(contentsOf: requirementsURL), requirementsAreValid(requirementsData) else { throw error("MLX 依赖清单校验失败") }
        let parent = runtimeRoot.deletingLastPathComponent()
        let funRuntime = parent.deletingLastPathComponent().appendingPathComponent("funasr/2")
        let sourcePython = ManagedFunASRRuntime(rootURL: funRuntime, fileManager: fileManager).pythonURL
        guard fileManager.isExecutableFile(atPath: sourcePython.path) else { throw error("需要先安装已验证的 Python 3.10 基础运行环境") }
        let staging = parent.appendingPathComponent(".mlx-asr-runtime-installing")
        let backup = parent.appendingPathComponent(".mlx-asr-runtime-backup")
        let cache = parent.appendingPathComponent(".mlx-asr-pip-cache")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        // Clone the proven standalone runtime without following model/cache symlinks.
        try run(URL(fileURLWithPath: "/usr/bin/ditto"), [funRuntime.path, staging.path])
        let python = staging.appendingPathComponent("python/bin/python3")
        try run(python, pipInstallArguments(requirementsURL: requirementsURL, cacheURL: cache))
        let managed = ManagedMLXASRRuntime(rootURL: staging, fileManager: fileManager)
        try managed.writeVersionMarker()
        guard case .ready = managed.state else { throw error("MLX 依赖安装后校验失败") }
        try? fileManager.removeItem(at: backup)
        if fileManager.fileExists(atPath: runtimeRoot.path) { try fileManager.moveItem(at: runtimeRoot, to: backup) }
        do { try fileManager.moveItem(at: staging, to: runtimeRoot); try? fileManager.removeItem(at: backup) }
        catch { if fileManager.fileExists(atPath: backup.path) { try? fileManager.moveItem(at: backup, to: runtimeRoot) }; throw error }
    }
    private nonisolated static func run(_ executable: URL, _ arguments: [String]) throws {
        let p = Process(), pipe = Pipe(); p.executableURL = executable; p.arguments = arguments; p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw error(message.isEmpty ? "MLX 运行环境安装命令失败" : String(message.suffix(4000)))
        }
    }
    private nonisolated static func error(_ message: String) -> NSError { NSError(domain: "com.waykingah.typewhale.mlx-asr-runtime", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
