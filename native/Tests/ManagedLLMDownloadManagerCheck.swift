import CryptoKit
import Foundation

@MainActor
private final class FakeArtifactDownloadTask: ManagedLLMArtifactDownloadTask {
    private(set) var wasCancelled = false

    func cancel(producingResumeData completion: @escaping @Sendable (Data?) -> Void) {
        wasCancelled = true
        completion(Data("resume".utf8))
    }
}

@MainActor
private final class FakeArtifactFetcher: ManagedLLMArtifactFetcher {
    struct Pending {
        let url: URL
        let resumeData: Data?
        let progress: (Int64, Int64) -> Void
        let completion: (Result<ManagedLLMDownloadedArtifact, Error>) -> Void
        let task: FakeArtifactDownloadTask
    }

    private(set) var pending: [Pending] = []

    func download(
        url: URL,
        resumeData: Data?,
        progress: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<ManagedLLMDownloadedArtifact, Error>) -> Void
    ) -> ManagedLLMArtifactDownloadTask {
        let task = FakeArtifactDownloadTask()
        pending.append(Pending(
            url: url,
            resumeData: resumeData,
            progress: progress,
            completion: completion,
            task: task
        ))
        return task
    }

    func reportProgress(at index: Int, written: Int64, expected: Int64) {
        pending[index].progress(written, expected)
    }

    func succeed(
        at index: Int,
        data: Data,
        statusCode: Int,
        temporaryRoot: URL
    ) throws {
        let location = temporaryRoot.appendingPathComponent("download-\(UUID().uuidString)")
        try data.write(to: location)
        let response = HTTPURLResponse(
            url: pending[index].url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        pending[index].completion(.success(.init(location: location, response: response)))
    }
}

@main
struct ManagedLLMDownloadManagerCheck {
    @MainActor
    static func main() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ManagedLLMDownloadManagerCheck-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let firstData = Data("one".utf8)
        let secondData = Data("four".utf8)
        let descriptor = ManagedLLMModelDescriptor(
            id: .qwen3_4BInstruct2507_4bit,
            displayName: "Fixture",
            detailText: "Fixture",
            directoryName: "fixture-model",
            repository: URL(string: "https://example.invalid/resolve")!,
            revision: "immutable-revision",
            recommendedMemoryGB: 1,
            artifacts: [
                .init(
                    name: "first.bin",
                    expectedBytes: Int64(firstData.count),
                    sha256: sha256(firstData)
                ),
                .init(
                    name: "second.bin",
                    expectedBytes: Int64(secondData.count),
                    sha256: sha256(secondData)
                ),
            ]
        )
        let rootSentinel = temporaryRoot.appendingPathComponent("keep.txt")
        try "keep".write(to: rootSentinel, atomically: true, encoding: .utf8)
        let fetcher = FakeArtifactFetcher()
        let manager = ManagedLLMDownloadManager(
            rootDirectory: temporaryRoot,
            descriptor: descriptor,
            fileManager: fileManager,
            fetcher: fetcher,
            availableCapacity: { _ in Int64.max }
        )

        precondition(manager.state == .missing)
        precondition(fetcher.pending.isEmpty, "download must be explicitly user-triggered")

        manager.install()
        precondition(fetcher.pending.count == 1)
        precondition(fetcher.pending[0].url == descriptor.downloadURL(for: descriptor.artifacts[0]))
        fetcher.reportProgress(at: 0, written: 2, expected: 3)
        precondition(manager.state == .installing(
            progress: 2.0 / 7.0,
            downloadedBytes: 2,
            totalBytes: 7
        ))
        try fetcher.succeed(at: 0, data: firstData, statusCode: 500, temporaryRoot: temporaryRoot)
        guard case .failed(let httpFailure) = manager.state else {
            preconditionFailure("HTTP failure must fail installation")
        }
        precondition(httpFailure.contains("HTTP 500"))
        precondition(!fileManager.fileExists(atPath: manager.destinationDirectory.path))

        manager.install()
        let wrongIndex = fetcher.pending.count - 1
        try fetcher.succeed(
            at: wrongIndex,
            data: Data("bad".utf8),
            statusCode: 200,
            temporaryRoot: temporaryRoot
        )
        guard case .failed(let validationFailure) = manager.state else {
            preconditionFailure("wrong artifact must fail validation")
        }
        precondition(validationFailure.contains("校验"))
        precondition(!fileManager.fileExists(atPath: manager.destinationDirectory.path))

        manager.install()
        let firstSuccessIndex = fetcher.pending.count - 1
        try fetcher.succeed(
            at: firstSuccessIndex,
            data: firstData,
            statusCode: 200,
            temporaryRoot: temporaryRoot
        )
        let secondSuccessIndex = fetcher.pending.count - 1
        precondition(secondSuccessIndex == firstSuccessIndex + 1)
        try fetcher.succeed(
            at: secondSuccessIndex,
            data: secondData,
            statusCode: 200,
            temporaryRoot: temporaryRoot
        )
        precondition(manager.state == .ready)
        let installedFirst = try Data(
            contentsOf: manager.destinationDirectory.appendingPathComponent("first.bin")
        )
        let installedSecond = try Data(
            contentsOf: manager.destinationDirectory.appendingPathComponent("second.bin")
        )
        precondition(installedFirst == firstData)
        precondition(installedSecond == secondData)

        try manager.delete()
        precondition(manager.state == .missing)
        precondition(fileManager.fileExists(atPath: rootSentinel.path))
        precondition(!fileManager.fileExists(atPath: manager.destinationDirectory.path))

        manager.install()
        let cancellationIndex = fetcher.pending.count - 1
        manager.cancel()
        precondition(fetcher.pending[cancellationIndex].task.wasCancelled)
        guard case .failed(let cancellationMessage) = manager.state else {
            preconditionFailure("cancelled download must be resumable failure state")
        }
        precondition(cancellationMessage.contains("已取消"))

        print("ManagedLLMDownloadManagerCheck passed")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
