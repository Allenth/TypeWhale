import Foundation

@MainActor
final class SenseVoiceModelInstaller: NSObject, URLSessionDownloadDelegate {
    enum State {
        case missing
        case ready
        case downloading(Double)
        case failed(String)
    }

    private let fileManager = FileManager.default
    private let modelDirectory: URL
    private let stagingDirectory: URL
    private let backupDirectory: URL
    private var artifactIndex = 0
    private var isInstalling = false
    private var session: URLSession!
    var onStateChange: ((State) -> Void)?

    init(modelDirectory: URL = SenseVoiceModelManifest.modelDirectory) {
        self.modelDirectory = modelDirectory
        stagingDirectory = modelDirectory.deletingLastPathComponent().appendingPathComponent(".sensevoice-native-installing")
        backupDirectory = modelDirectory.deletingLastPathComponent().appendingPathComponent(".sensevoice-native-backup")
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    var isModelReady: Bool {
        SenseVoiceModelManifest.isInstalled(at: modelDirectory)
    }

    func refresh() {
        let onStateChange = onStateChange
        DispatchQueue.global(qos: .userInitiated).async {
            let state: State = SenseVoiceModelManifest.preferredModelDirectory == nil ? .missing : .ready
            DispatchQueue.main.async {
                onStateChange?(state)
            }
        }
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        artifactIndex = 0
        do {
            try fileManager.createDirectory(
                at: modelDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let capacity = try modelDirectory.deletingLastPathComponent().resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
            if let capacity, capacity < SenseVoiceModelManifest.requiredFreeBytes {
                throw NSError(
                    domain: "com.waykingah.typespeaker.model-installer",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "可用磁盘空间不足，需要至少 1GB"]
                )
            }
            try? fileManager.removeItem(at: stagingDirectory)
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            emit(.downloading(0))
            downloadCurrentArtifact()
        } catch {
            fail("无法准备模型安装目录：\(error.localizedDescription)")
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard isInstalling, SenseVoiceModelManifest.artifacts.indices.contains(artifactIndex) else { return }
            let completed = SenseVoiceModelManifest.artifacts.prefix(artifactIndex).reduce(Int64(0)) { $0 + $1.expectedBytes }
            let total = SenseVoiceModelManifest.artifacts.reduce(Int64(0)) { $0 + $1.expectedBytes }
            let currentExpected = max(totalBytesExpectedToWrite, SenseVoiceModelManifest.artifacts[artifactIndex].expectedBytes)
            let boundedWritten = min(totalBytesWritten, currentExpected)
            emit(.downloading(min(1, Double(completed + boundedWritten) / Double(total))))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard isInstalling, SenseVoiceModelManifest.artifacts.indices.contains(artifactIndex) else { return }
            let artifact = SenseVoiceModelManifest.artifacts[artifactIndex]
            do {
                if let response = downloadTask.response as? HTTPURLResponse,
                   !(200...299).contains(response.statusCode) {
                    throw NSError(
                        domain: "com.waykingah.typespeaker.model-installer",
                        code: response.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "服务器返回 HTTP \(response.statusCode)"]
                    )
                }
                let destination = stagingDirectory.appendingPathComponent(artifact.installedName)
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: location, to: destination)
                guard try SenseVoiceModelManifest.sha256(of: destination) == artifact.sha256 else {
                    throw NSError(
                        domain: "com.waykingah.typespeaker.model-installer",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(artifact.installedName) 校验失败"]
                    )
                }
                artifactIndex += 1
                if artifactIndex < SenseVoiceModelManifest.artifacts.count {
                    downloadCurrentArtifact()
                } else {
                    try commitInstallation()
                    SenseVoiceModelManifest.rememberVerifiedInstallation(at: modelDirectory)
                    isInstalling = false
                    emit(.ready)
                }
            } catch {
                fail("模型安装失败：\(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            if let error, isInstalling {
                fail("模型下载失败：\(error.localizedDescription)")
            }
        }
    }

    private func downloadCurrentArtifact() {
        let artifact = SenseVoiceModelManifest.artifacts[artifactIndex]
        session.downloadTask(with: URL(string: "\(SenseVoiceModelManifest.repository)/\(artifact.remoteName)")!).resume()
    }

    private func commitInstallation() throws {
        try? fileManager.removeItem(at: backupDirectory)
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.moveItem(at: modelDirectory, to: backupDirectory)
        }
        do {
            try fileManager.moveItem(at: stagingDirectory, to: modelDirectory)
            try? fileManager.removeItem(at: backupDirectory)
        } catch {
            if fileManager.fileExists(atPath: backupDirectory.path) {
                try? fileManager.moveItem(at: backupDirectory, to: modelDirectory)
            }
            throw error
        }
    }

    private func fail(_ message: String) {
        isInstalling = false
        try? fileManager.removeItem(at: stagingDirectory)
        emit(.failed(message))
    }

    private func emit(_ state: State) {
        onStateChange?(state)
    }
}
