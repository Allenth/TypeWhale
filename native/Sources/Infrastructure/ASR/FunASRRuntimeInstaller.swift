import CryptoKit
import Foundation

@MainActor
final class FunASRRuntimeInstaller {
    enum State: Equatable {
        case missing
        case installing(String)
        case ready
        case failed(String)
    }

    private let runtimeRoot: URL
    private let requirementsURL: URL
    private let fileManager: FileManager
    private var installationTask: Task<Void, Never>?

    private(set) var state: State = .missing {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?

    init(
        runtimeRoot: URL,
        requirementsURL: URL,
        fileManager: FileManager = .default
    ) {
        self.runtimeRoot = runtimeRoot
        self.requirementsURL = requirementsURL
        self.fileManager = fileManager
        refresh()
    }

    deinit {
        installationTask?.cancel()
    }

    func refresh() {
        switch ManagedFunASRRuntime(rootURL: runtimeRoot, fileManager: fileManager).state {
        case .ready: state = .ready
        case .missing, .invalid: state = .missing
        }
    }

    func install() {
        guard installationTask == nil else { return }
        state = .installing("正在下载 Python 运行环境")
        let runtimeRoot = self.runtimeRoot
        let requirementsURL = self.requirementsURL
        let fileManager = self.fileManager

        installationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .utility) {
                    try Self.performInstallation(
                        runtimeRoot: runtimeRoot,
                        requirementsURL: requirementsURL,
                        fileManager: fileManager
                    )
                }.value
                installationTask = nil
                state = .ready
            } catch is CancellationError {
                installationTask = nil
                refresh()
            } catch {
                installationTask = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        installationTask?.cancel()
        installationTask = nil
        refresh()
    }

    nonisolated static func archiveIsValid(_ data: Data, expectedSHA256: String) -> Bool {
        sha256(data) == expectedSHA256.lowercased()
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func pythonDownloadArguments(destinationURL: URL) -> [String] {
        [
            "--fail", "--location", "--silent", "--show-error",
            "--retry", "8", "--retry-delay", "2", "--retry-max-time", "900",
            "--retry-all-errors", "--connect-timeout", "30",
            "--continue-at", "-",
            "--output", destinationURL.path,
            FunASRRuntimeManifest.pythonArchiveURL.absoluteString,
        ]
    }

    nonisolated static func pipInstallArguments(requirementsURL: URL, cacheURL: URL) -> [String] {
        [
            "-m", "pip", "install",
            "--disable-pip-version-check", "--no-input", "--no-user",
            "--retries", "10", "--resume-retries", "10", "--timeout", "120",
            "--cache-dir", cacheURL.path,
            "-r", requirementsURL.path,
        ]
    }

    private nonisolated static func performInstallation(
        runtimeRoot: URL,
        requirementsURL: URL,
        fileManager: FileManager
    ) throws {
        let parent = runtimeRoot.deletingLastPathComponent()
        let downloadCache = parent.appendingPathComponent(".funasr-download-cache", isDirectory: true)
        let pipCache = downloadCache.appendingPathComponent("pip", isDirectory: true)
        let cachedArchive = downloadCache.appendingPathComponent("python-\(FunASRRuntimeManifest.pythonVersion).tar.gz")
        let staging = parent.appendingPathComponent(".funasr-runtime-installing", isDirectory: true)
        let backup = parent.appendingPathComponent(".funasr-runtime-backup", isDirectory: true)
        try fileManager.createDirectory(at: pipCache, withIntermediateDirectories: true)
        try ensurePythonArchive(at: cachedArchive, fileManager: fileManager)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", cachedArchive.path, "-C", staging.path])

        let python = staging.appendingPathComponent("python/bin/python3")
        guard fileManager.isExecutableFile(atPath: python.path) else {
            throw error("解压后的 Python 不完整")
        }
        try run(python, pipInstallArguments(requirementsURL: requirementsURL, cacheURL: pipCache))
        let stagedRuntime = ManagedFunASRRuntime(rootURL: staging, fileManager: fileManager)
        try stagedRuntime.writeVersionMarker()
        guard case .ready = stagedRuntime.state else {
            throw error("FunASR 依赖安装后校验失败")
        }

        try? fileManager.removeItem(at: backup)
        if fileManager.fileExists(atPath: runtimeRoot.path) {
            try fileManager.moveItem(at: runtimeRoot, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: runtimeRoot)
            try? fileManager.removeItem(at: backup)
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: runtimeRoot)
            }
            throw error
        }
    }

    private nonisolated static func ensurePythonArchive(at archiveURL: URL, fileManager: FileManager) throws {
        if archiveFileIsValid(archiveURL) { return }
        try run(
            URL(fileURLWithPath: "/usr/bin/curl"),
            pythonDownloadArguments(destinationURL: archiveURL)
        )
        if archiveFileIsValid(archiveURL) { return }

        try? fileManager.removeItem(at: archiveURL)
        try run(
            URL(fileURLWithPath: "/usr/bin/curl"),
            pythonDownloadArguments(destinationURL: archiveURL)
        )
        guard archiveFileIsValid(archiveURL) else {
            try? fileManager.removeItem(at: archiveURL)
            throw error("Python 运行环境校验失败")
        }
    }

    private nonisolated static func archiveFileIsValid(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return archiveIsValid(data, expectedSHA256: FunASRRuntimeManifest.pythonArchiveSHA256)
    }

    private nonisolated static func run(_ executableURL: URL, _ arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw error(message?.isEmpty == false ? message! : "运行环境安装命令失败")
        }
    }

    private nonisolated static func error(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.funasr-runtime-installer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
