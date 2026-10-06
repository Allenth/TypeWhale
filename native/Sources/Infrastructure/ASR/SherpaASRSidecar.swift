import Darwin
import Foundation

struct SherpaASRTranscriptionResult: Equatable {
    let text: String
    let engine: String
    let loadSeconds: Double
    let durationSeconds: Double
}

final class SherpaASRSidecar: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let requestTimeout: TimeInterval
    private let queue = DispatchQueue(label: "com.waykingah.typewhale.sherpa-asr-sidecar", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorPipe: Pipe?
    private var loadedProvider: String?
    private var lastLoadSeconds: Double = 0

    init(executableURL: URL, arguments: [String] = [], requestTimeout: TimeInterval = 180) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.requestTimeout = requestTimeout
    }

    deinit { stopOnQueue() }

    func warmUp(providerID: String, modelDirectory: URL, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if loadedProvider != nil && loadedProvider != providerID { stopOnQueue() }
                let response = try send(.init(id: UUID().uuidString, command: .warmup, provider: providerID, modelDirectory: modelDirectory.path))
                guard response.ok else { throw failure(response.error ?? "Sherpa helper 预热失败") }
                loadedProvider = providerID
                lastLoadSeconds = response.loadSeconds ?? 0
                completion(.success(response.engine ?? "\(providerID)/sherpa-helper"))
            } catch {
                stopOnQueue(); completion(.failure(error))
            }
        }
    }

    func transcribe(providerID: String, audioURL: URL, completion: @escaping (Result<SherpaASRTranscriptionResult, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard loadedProvider == providerID else { throw failure("Sherpa 模型尚未预热") }
                let response = try send(.init(id: UUID().uuidString, command: .transcribe, provider: providerID, audioPath: audioURL.path))
                guard response.ok else { throw failure(response.error ?? "Sherpa helper 识别失败") }
                let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw failure("Sherpa helper 返回空文本") }
                completion(.success(.init(text: text, engine: response.engine ?? "\(providerID)/sherpa-helper", loadSeconds: lastLoadSeconds, durationSeconds: response.durationSeconds ?? 0)))
            } catch {
                stopOnQueue(); completion(.failure(error))
            }
        }
    }

    func stop() { queue.sync { stopOnQueue() } }

    private func ensureProcess() throws {
        if let process, process.isRunning, input != nil, output != nil { return }
        stopOnQueue()
        let process = Process(), inputPipe = Pipe(), outputPipe = Pipe(), errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        try process.run()
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        self.errorPipe = errorPipe
    }

    private func send(_ request: SherpaASRSidecarRequest) throws -> SherpaASRSidecarResponse {
        try ensureProcess()
        guard let input, let output else { throw failure("Sherpa helper 管道不可用") }
        var data = try JSONEncoder().encode(request); data.append(0x0A)
        try input.write(contentsOf: data)
        let response = try JSONDecoder().decode(SherpaASRSidecarResponse.self, from: readLine(output))
        guard response.id == request.id else { throw failure("Sherpa helper response id mismatch") }
        return response
    }

    private func readLine(_ handle: FileHandle) throws -> Data {
        let deadline = Date().addingTimeInterval(requestTimeout)
        var data = Data()
        while data.count < 1_048_576 {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw failure("Sherpa helper 识别超时") }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = Darwin.poll(&descriptor, 1, Int32(max(1, remaining * 1000)))
            if result == 0 { throw failure("Sherpa helper 识别超时") }
            if result < 0 { if errno == EINTR { continue }; throw failure("Sherpa helper 读取失败") }
            var byte: UInt8 = 0
            guard Darwin.read(handle.fileDescriptor, &byte, 1) == 1 else {
                let status: Int32
                if let process, !process.isRunning { status = process.terminationStatus } else { status = -1 }
                throw failure("Sherpa helper 已退出（status=\(status)）")
            }
            if byte == 0x0A { return data }
            data.append(byte)
        }
        throw failure("Sherpa helper 响应过大")
    }

    private func stopOnQueue() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? input?.close(); try? output?.close()
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil; input = nil; output = nil; errorPipe = nil
        loadedProvider = nil; lastLoadSeconds = 0
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "com.waykingah.typewhale.sherpa-asr-sidecar", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
