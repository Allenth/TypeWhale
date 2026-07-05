import Darwin
import Foundation

@MainActor
final class ManagedASRModelDownloader {
    enum State: Equatable {
        case missing
        case ready
        case downloading(progress: Double, downloadedBytes: Int64)
        case failed(String)
    }

    private struct ModelScopeCommand {
        let executableURL: URL
        let leadingArguments: [String]
    }

    private let fileManager: FileManager
    private let rootDirectory: URL
    private var states: [String: State] = [:]
    private var activeDownloads: Set<String> = []
    private var activeProcesses: [String: Process] = [:]
    private var cancelledDownloads: Set<String> = []
    private var downloadProgress: [String: Double] = [:]
    private var downloadedBytes: [String: Int64] = [:]
    private var downloadHealthTasks: [String: Task<Void, Never>] = [:]
    private var pendingAdoptionChecks: Set<String> = []

    var onStateChange: (() -> Void)?

    init(
        rootDirectory: URL = ManagedASRModelCatalog.rootDirectory(in: AppPaths.models),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        refresh()
        scheduleLaunchStagingRecovery()
    }

    func state(for model: ManagedASRModel) -> State {
        if activeDownloads.contains(model.id) {
            return states[model.id] ?? .downloading(
                progress: downloadProgress[model.id] ?? 0,
                downloadedBytes: downloadedBytes[model.id] ?? 0
            )
        }
        return states[model.id] ?? (model.isInstalled(in: rootDirectory, fileManager: fileManager) ? .ready : .missing)
    }

    func destinationDirectory(for model: ManagedASRModel) -> URL {
        model.directory(in: rootDirectory)
    }

    func refresh() {
        for model in ManagedASRModelCatalog.models where !activeDownloads.contains(model.id) {
            let staging = stagingDirectory(for: model)
            if model.isInstalled(in: rootDirectory, fileManager: fileManager) {
                states[model.id] = .ready
            } else if fileManager.fileExists(atPath: staging.path) {
                monitorExistingStaging(model, staging: staging)
            } else {
                states[model.id] = .missing
            }
        }
        onStateChange?()
    }

    func download(_ model: ManagedASRModel) {
        guard !activeDownloads.contains(model.id) else { return }
        guard let command = findModelScopeCommand() else {
            states[model.id] = .failed("未找到 modelscope 命令")
            onStateChange?()
            return
        }

        let rootDirectory = self.rootDirectory
        let destination = model.directory(in: rootDirectory)
        let staging = stagingDirectory(for: model)
        let backup = rootDirectory.appendingPathComponent(".\(model.relativeDirectoryName)-backup", isDirectory: true)
        let fileManager = self.fileManager

        activeDownloads.insert(model.id)
        downloadProgress[model.id] = 0
        downloadedBytes[model.id] = 0
        states[model.id] = .downloading(progress: 0, downloadedBytes: 0)
        startDownloadHealthCheck(model, staging: staging)
        onStateChange?()

        Task.detached(priority: .utility) {
            do {
                if Self.modelScopeDownloadIsRunning(localDirectory: staging) {
                    await MainActor.run {
                        guard self.activeDownloads.contains(model.id) else { return }
                        self.adoptRunningDownload(model, staging: staging)
                        self.onStateChange?()
                    }
                    return
                }

                try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
                try? fileManager.removeItem(at: staging)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = command.executableURL
                process.arguments = command.leadingArguments + [
                    "download",
                    "--model",
                    model.modelScopeID,
                    "--local_dir",
                    staging.path,
                    "--max-workers",
                    "4",
                ]
                let pipe = Pipe()
                let outputTail = DownloadOutputTail()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    outputTail.append(handle.availableData)
                }
                process.standardOutput = pipe
                process.standardError = pipe
                defer {
                    pipe.fileHandleForReading.readabilityHandler = nil
                }
                try process.run()
                await MainActor.run {
                    self.activeProcesses[model.id] = process
                }
                let progressTask = Task.detached(priority: .utility) {
                    while !Task.isCancelled {
                        let snapshot = Self.downloadSnapshot(in: staging, expectedBytes: model.estimatedBytes, fileManager: fileManager)
                        await MainActor.run {
                            guard self.activeDownloads.contains(model.id) else { return }
                            let previous = self.downloadProgress[model.id] ?? 0
                            let bounded = min(0.99, max(previous, snapshot.progress))
                            self.downloadProgress[model.id] = bounded
                            self.downloadedBytes[model.id] = snapshot.downloadedBytes
                            self.states[model.id] = .downloading(progress: bounded, downloadedBytes: snapshot.downloadedBytes)
                            self.onStateChange?()
                        }
                        try? await Task.sleep(nanoseconds: 700_000_000)
                    }
                }
                process.waitUntilExit()
                progressTask.cancel()

                let wasCancelled = await MainActor.run {
                    self.activeProcesses.removeValue(forKey: model.id)
                    return self.cancelledDownloads.remove(model.id) != nil
                }
                if wasCancelled {
                    try? fileManager.removeItem(at: staging)
                    await MainActor.run {
                        self.activeDownloads.remove(model.id)
                        self.downloadProgress.removeValue(forKey: model.id)
                        self.downloadedBytes.removeValue(forKey: model.id)
                        self.states[model.id] = .missing
                        self.onStateChange?()
                    }
                    return
                }

                guard process.terminationStatus == 0 else {
                    throw NSError(
                        domain: "com.waykingah.typewhale.managed-model-download",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: outputTail.string(defaultValue: "ModelScope 下载失败").trimmedFailureMessage(defaultValue: "ModelScope 下载失败")]
                    )
                }

                guard ManagedASRModelCatalog.directoryContainsRegularFile(staging, fileManager: fileManager) else {
                    throw NSError(
                        domain: "com.waykingah.typewhale.managed-model-download",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "下载目录为空或文件不可用"]
                    )
                }

                try? fileManager.removeItem(at: backup)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.moveItem(at: destination, to: backup)
                }
                do {
                    try fileManager.moveItem(at: staging, to: destination)
                    try? fileManager.removeItem(at: backup)
                } catch {
                    if fileManager.fileExists(atPath: backup.path) {
                        try? fileManager.moveItem(at: backup, to: destination)
                    }
                    throw error
                }

                await MainActor.run {
                    self.stopDownloadHealthCheck(for: model.id)
                    self.activeDownloads.remove(model.id)
                    self.downloadProgress.removeValue(forKey: model.id)
                    self.downloadedBytes.removeValue(forKey: model.id)
                    self.states[model.id] = .ready
                    self.onStateChange?()
                }
            } catch {
                try? fileManager.removeItem(at: staging)
                await MainActor.run {
                    guard self.activeDownloads.contains(model.id) else { return }
                    self.stopDownloadHealthCheck(for: model.id)
                    self.activeProcesses.removeValue(forKey: model.id)
                    self.activeDownloads.remove(model.id)
                    self.downloadProgress.removeValue(forKey: model.id)
                    self.downloadedBytes.removeValue(forKey: model.id)
                    if self.cancelledDownloads.remove(model.id) != nil {
                        self.states[model.id] = .missing
                    } else {
                        self.states[model.id] = .failed(error.localizedDescription)
                    }
                    self.onStateChange?()
                }
            }
        }
    }

    func cancelDownload(_ model: ManagedASRModel) {
        guard activeDownloads.contains(model.id) else { return }
        let process = activeProcesses.removeValue(forKey: model.id)
        if process != nil {
            cancelledDownloads.insert(model.id)
        } else {
            cancelledDownloads.remove(model.id)
        }
        activeDownloads.remove(model.id)
        downloadProgress.removeValue(forKey: model.id)
        downloadedBytes.removeValue(forKey: model.id)
        stopDownloadHealthCheck(for: model.id)
        states[model.id] = .missing
        onStateChange?()

        let staging = stagingDirectory(for: model)
        let fileManager = self.fileManager
        Task.detached(priority: .utility) {
            if let process, process.isRunning {
                Self.terminate(process: process)
            } else {
                Self.terminateModelScopeDownload(localDirectory: staging)
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            try? fileManager.removeItem(at: staging)
            if process == nil {
                await MainActor.run {
                    _ = self.cancelledDownloads.remove(model.id)
                }
            }
        }
    }

    private func stagingDirectory(for model: ManagedASRModel) -> URL {
        rootDirectory.appendingPathComponent(".\(model.relativeDirectoryName)-downloading", isDirectory: true)
    }

    private func startDownloadHealthCheck(_ model: ManagedASRModel, staging: URL) {
        stopDownloadHealthCheck(for: model.id)
        let fileManager = self.fileManager
        downloadHealthTasks[model.id] = Task.detached(priority: .utility) {
            var missingProcessTicks = 0
            var elapsedSeconds: TimeInterval = 0
            var secondsWithoutGrowth: TimeInterval = 0
            var lastDownloadedBytes: Int64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                elapsedSeconds += 2
                let shouldCheckDownload = await MainActor.run {
                    self.activeDownloads.contains(model.id)
                }
                guard shouldCheckDownload else {
                    continue
                }

                let hasTrackedProcess = await MainActor.run {
                    self.activeProcesses[model.id] != nil
                }
                let hasExternalProcess = Self.modelScopeDownloadIsRunning(localDirectory: staging)
                let snapshot = Self.downloadSnapshot(in: staging, expectedBytes: model.estimatedBytes, fileManager: fileManager)
                let downloadedBytes = snapshot.downloadedBytes

                if downloadedBytes > lastDownloadedBytes {
                    lastDownloadedBytes = downloadedBytes
                    secondsWithoutGrowth = 0
                    await MainActor.run {
                        guard self.activeDownloads.contains(model.id) else { return }
                        let bounded = max(self.downloadProgress[model.id] ?? 0, snapshot.progress)
                        self.downloadProgress[model.id] = bounded
                        self.downloadedBytes[model.id] = downloadedBytes
                        self.states[model.id] = .downloading(progress: bounded, downloadedBytes: downloadedBytes)
                        self.onStateChange?()
                    }
                } else {
                    secondsWithoutGrowth += 2
                }

                if hasTrackedProcess || hasExternalProcess {
                    missingProcessTicks = 0
                    if downloadedBytes == 0, elapsedSeconds >= 20 {
                        Self.terminateModelScopeDownload(localDirectory: staging)
                        try? fileManager.removeItem(at: staging)
                        await MainActor.run {
                            guard self.activeDownloads.contains(model.id) else { return }
                            self.activeProcesses.removeValue(forKey: model.id)
                            self.activeDownloads.remove(model.id)
                            self.downloadProgress.removeValue(forKey: model.id)
                            self.downloadedBytes.removeValue(forKey: model.id)
                            _ = self.downloadHealthTasks.removeValue(forKey: model.id)
                            self.states[model.id] = .failed("下载没有产生文件，请重试")
                            self.onStateChange?()
                        }
                        return
                    }
                    if downloadedBytes > 0, secondsWithoutGrowth >= 120 {
                        Self.terminateModelScopeDownload(localDirectory: staging)
                        await MainActor.run {
                            guard self.activeDownloads.contains(model.id) else { return }
                            self.activeProcesses.removeValue(forKey: model.id)
                            self.activeDownloads.remove(model.id)
                            self.downloadProgress.removeValue(forKey: model.id)
                            self.downloadedBytes.removeValue(forKey: model.id)
                            _ = self.downloadHealthTasks.removeValue(forKey: model.id)
                            self.states[model.id] = .failed("下载长时间无进展，请重试")
                            self.onStateChange?()
                        }
                        return
                    }
                    continue
                }

                missingProcessTicks += 1
                guard missingProcessTicks >= 2 else {
                    continue
                }

                if downloadedBytes == 0 {
                    try? fileManager.removeItem(at: staging)
                }
                await MainActor.run {
                    guard self.activeDownloads.contains(model.id),
                          self.activeProcesses[model.id] == nil else {
                        return
                    }
                    self.activeDownloads.remove(model.id)
                    self.downloadProgress.removeValue(forKey: model.id)
                    self.downloadedBytes.removeValue(forKey: model.id)
                    _ = self.downloadHealthTasks.removeValue(forKey: model.id)
                    self.states[model.id] = downloadedBytes == 0 ? .missing : .failed("下载进程未运行，请重试")
                    self.onStateChange?()
                }
                return
            }
        }
    }

    private func stopDownloadHealthCheck(for modelID: String) {
        downloadHealthTasks.removeValue(forKey: modelID)?.cancel()
    }

    private func monitorExistingStaging(_ model: ManagedASRModel, staging: URL) {
        guard !activeDownloads.contains(model.id) else { return }
        let snapshot = Self.downloadSnapshot(in: staging, expectedBytes: model.estimatedBytes, fileManager: fileManager)
        activeDownloads.insert(model.id)
        downloadProgress[model.id] = snapshot.progress
        downloadedBytes[model.id] = snapshot.downloadedBytes
        states[model.id] = .downloading(progress: snapshot.progress, downloadedBytes: snapshot.downloadedBytes)
        startDownloadHealthCheck(model, staging: staging)
    }

    private func scheduleLaunchStagingRecovery() {
        let rootDirectory = self.rootDirectory
        let fileManager = self.fileManager
        let snapshots = ManagedASRModelCatalog.models.compactMap { model -> (ManagedASRModel, URL)? in
            let staging = rootDirectory.appendingPathComponent(".\(model.relativeDirectoryName)-downloading", isDirectory: true)
            guard fileManager.fileExists(atPath: staging.path) else { return nil }
            return (model, staging)
        }
        guard !snapshots.isEmpty else { return }
        LaunchDiagnostics.mark("ManagedASR launch staging recovery scheduled count=\(snapshots.count)")

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in
            var changed = false
            for (_, staging) in snapshots {
                let currentBytes = Self.directorySize(staging, fileManager: .default)
                let hasProcess = Self.modelScopeDownloadIsRunning(localDirectory: staging)
                LaunchDiagnostics.mark("ManagedASR launch staging check path=\(staging.lastPathComponent) bytes=\(currentBytes) process=\(hasProcess)")
                if currentBytes == 0 {
                    if hasProcess {
                        Self.terminateModelScopeDownload(localDirectory: staging)
                    }
                    try? FileManager.default.removeItem(at: staging)
                    LaunchDiagnostics.mark("ManagedASR launch staging cleaned path=\(staging.lastPathComponent)")
                    changed = true
                }
            }
            guard changed else { return }
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func scheduleRunningDownloadAdoptionCheck(_ model: ManagedASRModel, staging: URL) {
        guard !pendingAdoptionChecks.contains(model.id) else { return }
        pendingAdoptionChecks.insert(model.id)
        let fileManager = self.fileManager
        Task.detached(priority: .utility) {
            let isRunning = Self.modelScopeDownloadIsRunning(localDirectory: staging)
            let downloadedBytes = isRunning ? 0 : Self.directorySize(staging, fileManager: fileManager)
            if !isRunning, downloadedBytes == 0 {
                try? fileManager.removeItem(at: staging)
            }
            await MainActor.run {
                self.pendingAdoptionChecks.remove(model.id)
                guard isRunning,
                      !self.activeDownloads.contains(model.id),
                      !model.isInstalled(in: self.rootDirectory, fileManager: self.fileManager) else {
                    return
                }
                self.adoptRunningDownload(model, staging: staging)
                self.onStateChange?()
            }
        }
    }

    private func adoptRunningDownload(_ model: ManagedASRModel, staging: URL) {
        activeDownloads.insert(model.id)
        let snapshot = Self.downloadSnapshot(in: staging, expectedBytes: model.estimatedBytes, fileManager: fileManager)
        downloadProgress[model.id] = snapshot.progress
        downloadedBytes[model.id] = snapshot.downloadedBytes
        states[model.id] = .downloading(progress: snapshot.progress, downloadedBytes: snapshot.downloadedBytes)
        startDownloadHealthCheck(model, staging: staging)
        let fileManager = self.fileManager
        Task.detached(priority: .utility) {
            while Self.modelScopeDownloadIsRunning(localDirectory: staging) {
                let snapshot = Self.downloadSnapshot(in: staging, expectedBytes: model.estimatedBytes, fileManager: fileManager)
                await MainActor.run {
                    guard self.activeDownloads.contains(model.id) else { return }
                    let previous = self.downloadProgress[model.id] ?? 0
                    let bounded = min(0.99, max(previous, snapshot.progress))
                    self.downloadProgress[model.id] = bounded
                    self.downloadedBytes[model.id] = snapshot.downloadedBytes
                    self.states[model.id] = .downloading(progress: bounded, downloadedBytes: snapshot.downloadedBytes)
                    self.onStateChange?()
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            await MainActor.run {
                guard self.activeDownloads.contains(model.id) else { return }
                self.stopDownloadHealthCheck(for: model.id)
                self.activeDownloads.remove(model.id)
                self.downloadProgress.removeValue(forKey: model.id)
                self.downloadedBytes.removeValue(forKey: model.id)
                self.states[model.id] = .failed("下载进程已结束，请重试以完成提交")
                self.onStateChange?()
            }
        }
    }

    private nonisolated static func downloadSnapshot(in directory: URL, expectedBytes: Int64, fileManager: FileManager) -> (progress: Double, downloadedBytes: Int64) {
        guard expectedBytes > 0 else { return (0, 0) }
        let downloaded = directorySize(directory, fileManager: fileManager)
        guard downloaded > 0 else { return (0, 0) }
        return (min(0.99, max(0, Double(downloaded) / Double(expectedBytes))), downloaded)
    }

    private nonisolated static func directorySize(_ directory: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private nonisolated static func modelScopeDownloadIsRunning(localDirectory: URL) -> Bool {
        !modelScopeDownloadPIDs(localDirectory: localDirectory).isEmpty
    }

    private nonisolated static func terminateModelScopeDownload(localDirectory: URL) {
        signalModelScopeDownload(localDirectory: localDirectory, signal: "-TERM")
        Thread.sleep(forTimeInterval: 0.4)
        signalModelScopeDownload(localDirectory: localDirectory, signal: "-KILL")
    }

    private nonisolated static func terminate(process: Process) {
        process.terminate()
        Thread.sleep(forTimeInterval: 0.4)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private nonisolated static func signalModelScopeDownload(localDirectory: URL, signal: String) {
        for pid in modelScopeDownloadPIDs(localDirectory: localDirectory) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = [signal, String(pid)]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private nonisolated static func modelScopeDownloadPIDs(localDirectory: URL) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "pid=", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return Self.parseModelScopeDownloadPIDs(output: output, localDirectory: localDirectory)
        } catch {
            return []
        }
    }

    nonisolated static func parseModelScopeDownloadPIDs(output: String, localDirectory: URL) -> [Int32] {
        return output
            .split(separator: "\n")
            .compactMap { line -> Int32? in
                guard line.contains("modelscope")
                    && line.contains("download")
                    && line.contains(localDirectory.path) else {
                    return nil
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let pidText = trimmed.split(separator: " ").first,
                      let pid = Int32(pidText) else {
                    return nil
                }
                return pid
            }
    }

    private func findModelScopeCommand() -> ModelScopeCommand? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["TYPEWHALE_MODELSCOPE_CLI"],
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/modelscope",
            "/opt/homebrew/bin/modelscope",
            "/usr/local/bin/modelscope",
        ].compactMap { $0 }.filter { !$0.isEmpty }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return ModelScopeCommand(executableURL: URL(fileURLWithPath: path), leadingArguments: [])
        }
        if fileManager.isExecutableFile(atPath: "/usr/bin/env") {
            return ModelScopeCommand(executableURL: URL(fileURLWithPath: "/usr/bin/env"), leadingArguments: ["modelscope"])
        }
        return nil
    }
}

private extension String {
    func trimmedFailureMessage(defaultValue: String) -> String {
        let lines = split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.suffix(3).joined(separator: "\n").isEmpty ? defaultValue : lines.suffix(3).joined(separator: "\n")
    }
}

private final class DownloadOutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private let limit = 64 * 1024
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > limit {
            data.removeFirst(data.count - limit)
        }
        lock.unlock()
    }

    func string(defaultValue: String) -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        guard !snapshot.isEmpty else { return defaultValue }
        return String(data: snapshot, encoding: .utf8) ?? defaultValue
    }
}
