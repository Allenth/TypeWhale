import Darwin
import Foundation

struct FunASRTranscriptionResult: Equatable {
    let text: String
    let engine: String
    let durationSeconds: Double
    let hotwordStrategy: String?
    let hotwordCount: Int

    init(
        text: String,
        engine: String,
        durationSeconds: Double,
        hotwordStrategy: String? = nil,
        hotwordCount: Int = 0
    ) {
        self.text = text
        self.engine = engine
        self.durationSeconds = durationSeconds
        self.hotwordStrategy = hotwordStrategy
        self.hotwordCount = hotwordCount
    }
}

final class FunASRSidecar: @unchecked Sendable {
    private let pythonURL: URL
    private let workerURL: URL
    private let requestTimeout: TimeInterval
    private let environment: [String: String]
    private let queue = DispatchQueue(label: "com.waykingah.typewhale.funasr-sidecar", qos: .userInitiated)

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorPipe: Pipe?
    private var loadedProviderID: String?

    init(
        pythonURL: URL,
        workerURL: URL,
        requestTimeout: TimeInterval = 30,
        environment: [String: String] = [:]
    ) {
        self.pythonURL = pythonURL
        self.workerURL = workerURL
        self.requestTimeout = requestTimeout
        self.environment = environment
    }

    deinit {
        stopOnQueue()
    }

    func warmUp(
        providerID: String,
        modelDirectory: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if loadedProviderID != nil, loadedProviderID != providerID {
                    stopOnQueue()
                }
                let response = try send(FunASRSidecarRequest(
                    id: UUID().uuidString,
                    command: .warmup,
                    provider: providerID,
                    modelDirectory: modelDirectory.path
                ))
                guard response.ok else { throw sidecarError(response.error ?? "FunASR 预热失败") }
                loadedProviderID = providerID
                completion(.success(response.engine ?? "\(providerID)/funasr-python"))
            } catch {
                stopOnQueue()
                completion(.failure(error))
            }
        }
    }

    func transcribe(
        providerID: String,
        audioURL: URL,
        hotwords: [String],
        completion: @escaping (Result<FunASRTranscriptionResult, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard loadedProviderID == providerID else {
                    throw sidecarError("FunASR provider 尚未预热：\(providerID)")
                }
                guard let hotwordStrategy = hotwordStrategy(for: providerID) else {
                    throw sidecarError("FunASR provider 不受支持：\(providerID)")
                }
                let response = try send(FunASRSidecarRequest(
                    id: UUID().uuidString,
                    command: .transcribe,
                    provider: providerID,
                    audioPath: audioURL.path,
                    hotwords: hotwords,
                    hotwordStrategy: hotwordStrategy
                ))
                guard response.ok else { throw sidecarError(response.error ?? "FunASR 识别失败") }
                let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw sidecarError("FunASR 返回空文本") }
                guard response.hotwordStrategy == hotwordStrategy else {
                    throw sidecarError("FunASR worker 回显了不一致的热词格式")
                }
                completion(.success(FunASRTranscriptionResult(
                    text: text,
                    engine: response.engine ?? "\(providerID)/funasr-python",
                    durationSeconds: response.durationSeconds ?? 0,
                    hotwordStrategy: response.hotwordStrategy,
                    hotwordCount: response.hotwordCount ?? 0
                )))
            } catch {
                stopOnQueue()
                completion(.failure(error))
            }
        }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func hotwordStrategy(for providerID: String) -> String? {
        switch providerID {
        case "fun-asr-nano-2512":
            return "native_list"
        default:
            return nil
        }
    }

    private func ensureProcess() throws {
        if let process, process.isRunning, inputHandle != nil, outputHandle != nil { return }
        stopOnQueue()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = pythonURL
        process.arguments = [workerURL.path]
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            LaunchDiagnostics.mark("funasr_worker stderr=\(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        try process.run()
        self.process = process
        inputHandle = input.fileHandleForWriting
        outputHandle = output.fileHandleForReading
        errorPipe = error
    }

    private func send(_ request: FunASRSidecarRequest) throws -> FunASRSidecarResponse {
        try ensureProcess()
        guard let inputHandle, let outputHandle else { throw sidecarError("FunASR sidecar 管道不可用") }
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
        let responseData = try readLine(from: outputHandle, timeout: requestTimeout)
        let response = try JSONDecoder().decode(FunASRSidecarResponse.self, from: responseData)
        guard response.id == request.id else {
            throw sidecarError("FunASR response id mismatch")
        }
        return response
    }

    private func readLine(from handle: FileHandle, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        while data.count < 1_048_576 {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw sidecarError("FunASR 识别超时") }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = Darwin.poll(&descriptor, 1, Int32(max(1, remaining * 1000)))
            if result == 0 { throw sidecarError("FunASR 识别超时") }
            if result < 0 {
                if errno == EINTR { continue }
                throw sidecarError("FunASR sidecar 读取失败")
            }
            var byte: UInt8 = 0
            let count = Darwin.read(handle.fileDescriptor, &byte, 1)
            guard count == 1 else { throw sidecarError("FunASR sidecar 已退出") }
            if byte == 0x0A { return data }
            data.append(byte)
        }
        throw sidecarError("FunASR sidecar 响应过大")
    }

    private func stopOnQueue() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
        errorPipe = nil
        loadedProviderID = nil
    }

    private func sidecarError(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.funasr-sidecar",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
