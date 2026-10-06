import Foundation

enum ManagedLLMInstallState: Equatable {
    case validating
    case missing
    case ready
    case installing(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case failed(String)
}

struct ManagedLLMDownloadedArtifact {
    let location: URL
    let response: HTTPURLResponse?
}

@MainActor
protocol ManagedLLMArtifactDownloadTask: AnyObject {
    func cancel(producingResumeData completion: @escaping @Sendable (Data?) -> Void)
}

@MainActor
protocol ManagedLLMArtifactFetcher: AnyObject {
    func download(
        url: URL,
        resumeData: Data?,
        progress: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<ManagedLLMDownloadedArtifact, Error>) -> Void
    ) -> ManagedLLMArtifactDownloadTask
}

@MainActor
final class ManagedLLMDownloadManager {
    static let requiredFreeBytes: Int64 = 15 * 1_024 * 1_024 * 1_024

    private(set) var state: ManagedLLMInstallState
    let destinationDirectory: URL
    var onStateChange: ((ManagedLLMInstallState) -> Void)?

    private let rootDirectory: URL
    private let descriptor: ManagedLLMModelDescriptor
    private let fileManager: FileManager
    private let fetcher: ManagedLLMArtifactFetcher
    private let availableCapacity: (URL) throws -> Int64?

    private var artifactIndex = 0
    private var completedBytes: Int64 = 0
    private var activeTask: ManagedLLMArtifactDownloadTask?
    private var resumeDataByArtifact: [String: Data] = [:]
    private var isInstalling = false
    private var installationGeneration = UUID()
    private var refreshGeneration = UUID()

    init(
        rootDirectory: URL,
        descriptor: ManagedLLMModelDescriptor = ManagedLLMModelCatalog.qwen3_4BInstruct2507_4bit,
        fileManager: FileManager = .default,
        fetcher: ManagedLLMArtifactFetcher? = nil,
        availableCapacity: @escaping (URL) throws -> Int64? = { url in
            try url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) {
        self.rootDirectory = rootDirectory
        self.descriptor = descriptor
        self.fileManager = fileManager
        self.fetcher = fetcher ?? URLSessionManagedLLMArtifactFetcher.shared
        self.availableCapacity = availableCapacity
        destinationDirectory = rootDirectory.appendingPathComponent(
            descriptor.directoryName,
            isDirectory: true
        )
        state = fileManager.fileExists(atPath: destinationDirectory.path)
            ? .validating
            : .missing
    }

    convenience init(
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.init(
            rootDirectory: ManagedLLMModelCatalog.rootDirectory(in: modelsDirectory),
            fileManager: fileManager
        )
    }

    func refresh() {
        guard !isInstalling else { return }
        guard fileManager.fileExists(atPath: destinationDirectory.path) else {
            emit(.missing)
            return
        }
        let generation = UUID()
        refreshGeneration = generation
        emit(.validating)
        let rootDirectory = self.rootDirectory
        let descriptor = self.descriptor
        Task.detached(priority: .utility) {
            let readiness = ManagedLLMModelRegistry(
                rootURL: rootDirectory,
                descriptors: [descriptor],
                fileManager: .default
            ).readiness(for: descriptor.id)
            await MainActor.run {
                guard self.refreshGeneration == generation, !self.isInstalling else { return }
                switch readiness {
                case .ready:
                    self.emit(.ready)
                case .missing:
                    self.emit(.missing)
                case .invalid(let reason):
                    self.emit(.failed(reason))
                }
            }
        }
    }

    func install() {
        guard !isInstalling else { return }
        if case .ready = registry.readiness(for: descriptor.id) {
            emit(.ready)
            return
        }

        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            if let available = try availableCapacity(rootDirectory),
               available < Self.requiredFreeBytes {
                throw failure("可用磁盘空间不足，需要至少 15 GB")
            }
            if !fileManager.fileExists(atPath: stagingDirectory.path) {
                try fileManager.createDirectory(
                    at: stagingDirectory,
                    withIntermediateDirectories: true
                )
            }
            (artifactIndex, completedBytes) = try resumablePosition()
            isInstalling = true
            installationGeneration = UUID()
            if artifactIndex == descriptor.artifacts.count {
                try commitInstallation()
                isInstalling = false
                emit(.ready)
                return
            }
            emit(.installing(
                progress: Double(completedBytes) / Double(descriptor.totalBytes),
                downloadedBytes: completedBytes,
                totalBytes: descriptor.totalBytes
            ))
            downloadCurrentArtifact(generation: installationGeneration)
        } catch {
            fail("无法准备模型安装：\(error.localizedDescription)")
        }
    }

    func cancel() {
        guard isInstalling else { return }
        isInstalling = false
        let artifactName = descriptor.artifacts[artifactIndex].name
        let task = activeTask
        activeTask = nil
        installationGeneration = UUID()
        task?.cancel { [weak self] data in
            Task { @MainActor in
                guard let self, let data else { return }
                self.resumeDataByArtifact[artifactName] = data
            }
        }
        emit(.failed("下载已取消，可继续安装"))
    }

    func delete() throws {
        cancel()
        for ownedURL in [destinationDirectory, stagingDirectory, backupDirectory] {
            if fileManager.fileExists(atPath: ownedURL.path) {
                try fileManager.removeItem(at: ownedURL)
            }
        }
        resumeDataByArtifact.removeAll()
        emit(.missing)
    }

    private var registry: ManagedLLMModelRegistry {
        ManagedLLMModelRegistry(
            rootURL: rootDirectory,
            descriptors: [descriptor],
            fileManager: fileManager
        )
    }

    private var stagingDirectory: URL {
        rootDirectory.appendingPathComponent(
            ".installing-\(descriptor.id.rawValue)",
            isDirectory: true
        )
    }

    private var backupDirectory: URL {
        rootDirectory.appendingPathComponent(
            ".backup-\(descriptor.id.rawValue)",
            isDirectory: true
        )
    }

    private func resumablePosition() throws -> (Int, Int64) {
        var completed: Int64 = 0
        for (index, artifact) in descriptor.artifacts.enumerated() {
            let fileURL = stagingDirectory.appendingPathComponent(artifact.name)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return (index, completed)
            }
            guard try validates(fileURL, artifact: artifact) else {
                try fileManager.removeItem(at: fileURL)
                return (index, completed)
            }
            completed += artifact.expectedBytes
        }
        return (descriptor.artifacts.count, completed)
    }

    private func downloadCurrentArtifact(generation: UUID) {
        guard isInstalling,
              generation == installationGeneration,
              descriptor.artifacts.indices.contains(artifactIndex) else { return }
        let artifact = descriptor.artifacts[artifactIndex]
        activeTask = fetcher.download(
            url: descriptor.downloadURL(for: artifact),
            resumeData: resumeDataByArtifact[artifact.name],
            progress: { [weak self] written, expected in
                guard let self,
                      self.isInstalling,
                      generation == self.installationGeneration else { return }
                let expectedBytes = max(expected, artifact.expectedBytes)
                let bounded = min(max(0, written), expectedBytes)
                let downloaded = min(
                    self.descriptor.totalBytes,
                    self.completedBytes + bounded
                )
                self.emit(.installing(
                    progress: min(1, Double(downloaded) / Double(self.descriptor.totalBytes)),
                    downloadedBytes: downloaded,
                    totalBytes: self.descriptor.totalBytes
                ))
            },
            completion: { [weak self] result in
                guard let self,
                      self.isInstalling,
                      generation == self.installationGeneration else { return }
                self.activeTask = nil
                self.handleDownloadResult(result, artifact: artifact, generation: generation)
            }
        )
    }

    private func handleDownloadResult(
        _ result: Result<ManagedLLMDownloadedArtifact, Error>,
        artifact: ManagedLLMArtifact,
        generation: UUID
    ) {
        do {
            let downloaded = try result.get()
            if let statusCode = downloaded.response?.statusCode,
               !(200...299).contains(statusCode) {
                try? fileManager.removeItem(at: downloaded.location)
                throw failure("服务器返回 HTTP \(statusCode)")
            }
            guard try validates(downloaded.location, artifact: artifact) else {
                try? fileManager.removeItem(at: downloaded.location)
                throw failure("模型文件校验失败：\(artifact.name)")
            }

            let destination = stagingDirectory.appendingPathComponent(artifact.name)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: downloaded.location, to: destination)
            resumeDataByArtifact.removeValue(forKey: artifact.name)
            completedBytes += artifact.expectedBytes
            artifactIndex += 1

            if artifactIndex < descriptor.artifacts.count {
                downloadCurrentArtifact(generation: generation)
            } else {
                try commitInstallation()
                isInstalling = false
                emit(.ready)
            }
        } catch {
            fail("模型安装失败：\(error.localizedDescription)")
        }
    }

    private func validates(
        _ fileURL: URL,
        artifact: ManagedLLMArtifact
    ) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == artifact.expectedBytes else {
            return false
        }
        return try ManagedLLMModelRegistry.sha256(of: fileURL) == artifact.sha256
    }

    private func commitInstallation() throws {
        switch registryForStaging.readiness(for: descriptor.id) {
        case .ready:
            break
        case .missing:
            throw failure("暂存模型不完整")
        case .invalid(let reason):
            throw failure(reason)
        }

        try? fileManager.removeItem(at: backupDirectory)
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.moveItem(at: destinationDirectory, to: backupDirectory)
        }
        do {
            try fileManager.moveItem(at: stagingDirectory, to: destinationDirectory)
            guard case .ready = registry.readiness(for: descriptor.id) else {
                throw failure("安装后的模型校验失败")
            }
            try? fileManager.removeItem(at: backupDirectory)
        } catch {
            try? fileManager.removeItem(at: destinationDirectory)
            if fileManager.fileExists(atPath: backupDirectory.path) {
                try? fileManager.moveItem(at: backupDirectory, to: destinationDirectory)
            }
            throw error
        }
    }

    private var registryForStaging: ManagedLLMModelRegistry {
        let stagingDescriptor = ManagedLLMModelDescriptor(
            id: descriptor.id,
            displayName: descriptor.displayName,
            detailText: descriptor.detailText,
            directoryName: stagingDirectory.lastPathComponent,
            repository: descriptor.repository,
            revision: descriptor.revision,
            recommendedMemoryGB: descriptor.recommendedMemoryGB,
            artifacts: descriptor.artifacts
        )
        return ManagedLLMModelRegistry(
            rootURL: rootDirectory,
            descriptors: [stagingDescriptor],
            fileManager: fileManager
        )
    }

    private func fail(_ message: String) {
        isInstalling = false
        activeTask = nil
        installationGeneration = UUID()
        emit(.failed(message))
    }

    private func emit(_ newState: ManagedLLMInstallState) {
        state = newState
        onStateChange?(newState)
    }

    private func failure(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.managed-llm-download",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

@MainActor
private final class URLSessionArtifactDownloadToken: ManagedLLMArtifactDownloadTask {
    private let task: URLSessionDownloadTask

    init(task: URLSessionDownloadTask) {
        self.task = task
    }

    func cancel(producingResumeData completion: @escaping @Sendable (Data?) -> Void) {
        task.cancel(byProducingResumeData: completion)
    }
}

@MainActor
final class URLSessionManagedLLMArtifactFetcher: NSObject, ManagedLLMArtifactFetcher {
    static let shared = URLSessionManagedLLMArtifactFetcher()

    private struct Context {
        let progress: (Int64, Int64) -> Void
        let completion: (Result<ManagedLLMDownloadedArtifact, Error>) -> Void
    }

    private var contexts: [Int: Context] = [:]
    private lazy var session = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    func download(
        url: URL,
        resumeData: Data?,
        progress: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<ManagedLLMDownloadedArtifact, Error>) -> Void
    ) -> ManagedLLMArtifactDownloadTask {
        let task = resumeData.map { session.downloadTask(withResumeData: $0) }
            ?? session.downloadTask(with: url)
        contexts[task.taskIdentifier] = Context(
            progress: progress,
            completion: completion
        )
        task.resume()
        return URLSessionArtifactDownloadToken(task: task)
    }
}

extension URLSessionManagedLLMArtifactFetcher: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        _ = session
        _ = bytesWritten
        Task { @MainActor in
            self.contexts[downloadTask.taskIdentifier]?.progress(
                totalBytesWritten,
                totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        _ = session
        let persistentLocation = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-llm-download-\(UUID().uuidString)")
        let copyResult: Result<URL, Error>
        do {
            try FileManager.default.moveItem(at: location, to: persistentLocation)
            copyResult = .success(persistentLocation)
        } catch {
            copyResult = .failure(error)
        }
        Task { @MainActor in
            guard let context = self.contexts.removeValue(
                forKey: downloadTask.taskIdentifier
            ) else { return }
            switch copyResult {
            case .success(let savedLocation):
                context.completion(.success(.init(
                    location: savedLocation,
                    response: downloadTask.response as? HTTPURLResponse
                )))
            case .failure(let error):
                context.completion(.failure(error))
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        _ = session
        guard let error else { return }
        Task { @MainActor in
            guard let context = self.contexts.removeValue(
                forKey: task.taskIdentifier
            ) else { return }
            context.completion(.failure(error))
        }
    }
}
