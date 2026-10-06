import Darwin
import Foundation

protocol ManagedLLMRuntime: AnyObject {
    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse
    func cancelCurrentRequest()
    func stop()
}

protocol ManagedLLMRuntimeActivityReporting: AnyObject {
    var hasActiveRequest: Bool { get }
}

protocol ManagedLLMRuntimeIdlePerforming: AnyObject {
    func performIfIdle(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse
}

enum ManagedLLMRuntimeError: Error, Equatable, LocalizedError {
    case cancelled
    case timedOut
    case helperExited
    case responseTooLarge
    case responseIDMismatch
    case invalidResponse
    case unavailable
    case busy

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "请求已取消"
        case .timedOut:
            return "本地模型响应超时"
        case .helperExited:
            return "本地模型进程意外退出"
        case .responseTooLarge:
            return "本地模型响应超过安全上限"
        case .responseIDMismatch:
            return "本地模型响应标识不匹配"
        case .invalidResponse:
            return "本地模型返回了无效响应"
        case .unavailable:
            return "本地模型运行环境不可用"
        case .busy:
            return "本地模型正在处理其他任务"
        }
    }
}

final class ManagedMLXLLMRuntime: ManagedLLMRuntime,
    ManagedLLMRuntimeActivityReporting,
    ManagedLLMRuntimeIdlePerforming,
    @unchecked Sendable
{
    private static let maximumResponseBytes = 1_048_576

    private let pythonURL: URL
    private let workerURL: URL
    private let requestTimeout: TimeInterval
    private let queue = DispatchQueue(
        label: "com.waykingah.typewhale.managed-mlx-llm",
        qos: .userInitiated
    )
    private let stateLock = NSLock()

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorPipe: Pipe?
    private var activeRequestID: String?
    private var pendingRequestIDs: Set<String> = []
    private var cancelledRequestIDs: Set<String> = []

    init(
        pythonURL: URL,
        workerURL: URL,
        requestTimeout: TimeInterval = 180
    ) {
        self.pythonURL = pythonURL
        self.workerURL = workerURL
        self.requestTimeout = requestTimeout
    }

    deinit {
        terminateOwnedProcess()
    }

    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        try await perform(request, onlyIfIdle: false)
    }

    func performIfIdle(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        try await perform(request, onlyIfIdle: true)
    }

    private func perform(
        _ request: ManagedMLXLLMRequest,
        onlyIfIdle: Bool
    ) async throws -> ManagedMLXLLMResponse {
        try Task.checkCancellation()
        try reserve(requestID: request.id, onlyIfIdle: onlyIfIdle)

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<ManagedMLXLLMResponse, Error>) in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: ManagedLLMRuntimeError.unavailable)
                        return
                    }
                    do {
                        continuation.resume(returning: try self.performOnQueue(request))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.cancel(requestID: request.id)
        }
    }

    func cancelCurrentRequest() {
        stateLock.lock()
        let requestID = activeRequestID
        stateLock.unlock()
        if let requestID {
            cancel(requestID: requestID)
        }
    }

    func stop() {
        stateLock.lock()
        if let activeRequestID {
            cancelledRequestIDs.insert(activeRequestID)
        }
        stateLock.unlock()
        terminateOwnedProcess()
    }

    var isRunningForTesting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process?.isRunning == true
    }

    var hasActiveRequest: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeRequestID != nil || !pendingRequestIDs.isEmpty
    }

    var ownedProcessIdentifier: pid_t? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    private func performOnQueue(_ request: ManagedMLXLLMRequest) throws -> ManagedMLXLLMResponse {
        beginReservedRequest(request.id)
        defer {
            stateLock.lock()
            activeRequestID = nil
            cancelledRequestIDs.remove(request.id)
            stateLock.unlock()
        }

        if isCancelled(request.id) {
            throw ManagedLLMRuntimeError.cancelled
        }

        var crashCount = 0
        while true {
            do {
                let response = try sendOnce(request)
                guard response.id == request.id else {
                    terminateOwnedProcess()
                    throw ManagedLLMRuntimeError.responseIDMismatch
                }
                return response
            } catch let error as ManagedLLMRuntimeError {
                if isCancelled(request.id) {
                    terminateOwnedProcess()
                    throw ManagedLLMRuntimeError.cancelled
                }
                guard error == .helperExited, crashCount == 0 else {
                    terminateOwnedProcess()
                    throw error
                }
                crashCount += 1
                terminateOwnedProcess()
            } catch {
                terminateOwnedProcess()
                throw ManagedLLMRuntimeError.invalidResponse
            }
        }
    }

    private func sendOnce(_ request: ManagedMLXLLMRequest) throws -> ManagedMLXLLMResponse {
        try ensureProcess()
        if isCancelled(request.id) {
            terminateOwnedProcess()
            throw ManagedLLMRuntimeError.cancelled
        }

        stateLock.lock()
        let inputHandle = self.inputHandle
        let outputHandle = self.outputHandle
        stateLock.unlock()
        guard let inputHandle, let outputHandle else {
            throw ManagedLLMRuntimeError.unavailable
        }

        do {
            var requestData = try JSONEncoder().encode(request)
            requestData.append(0x0A)
            try inputHandle.write(contentsOf: requestData)
        } catch {
            throw ManagedLLMRuntimeError.helperExited
        }

        let responseData = try readLine(
            from: outputHandle,
            deadline: Date().addingTimeInterval(requestTimeout)
        )
        do {
            return try JSONDecoder().decode(ManagedMLXLLMResponse.self, from: responseData)
        } catch {
            throw ManagedLLMRuntimeError.invalidResponse
        }
    }

    private func ensureProcess() throws {
        stateLock.lock()
        let isReady = process?.isRunning == true && inputHandle != nil && outputHandle != nil
        stateLock.unlock()
        if isReady { return }

        terminateOwnedProcess()

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = pythonURL
        process.arguments = [workerURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "TOKENIZERS_PARALLELISM": "false",
        ]) { _, new in new }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ManagedLLMRuntimeError.unavailable
        }

        stateLock.lock()
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        self.errorPipe = errorPipe
        stateLock.unlock()
    }

    private func readLine(from handle: FileHandle, deadline: Date) throws -> Data {
        var data = Data()
        while data.count < Self.maximumResponseBytes {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                terminateOwnedProcess()
                throw ManagedLLMRuntimeError.timedOut
            }

            var descriptor = pollfd(
                fd: handle.fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let result = Darwin.poll(
                &descriptor,
                1,
                Int32(max(1, min(Double(Int32.max), remaining * 1_000)))
            )
            if result == 0 {
                terminateOwnedProcess()
                throw ManagedLLMRuntimeError.timedOut
            }
            if result < 0 {
                if errno == EINTR { continue }
                throw ManagedLLMRuntimeError.helperExited
            }

            var byte: UInt8 = 0
            let count = Darwin.read(handle.fileDescriptor, &byte, 1)
            guard count == 1 else {
                throw ManagedLLMRuntimeError.helperExited
            }
            if byte == 0x0A {
                return data
            }
            data.append(byte)
        }

        terminateOwnedProcess()
        throw ManagedLLMRuntimeError.responseTooLarge
    }

    private func reserve(requestID: String, onlyIfIdle: Bool) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if onlyIfIdle && (activeRequestID != nil || !pendingRequestIDs.isEmpty) {
            throw ManagedLLMRuntimeError.busy
        }
        pendingRequestIDs.insert(requestID)
    }

    private func beginReservedRequest(_ requestID: String) {
        stateLock.lock()
        pendingRequestIDs.remove(requestID)
        activeRequestID = requestID
        stateLock.unlock()
    }

    private func cancel(requestID: String) {
        stateLock.lock()
        cancelledRequestIDs.insert(requestID)
        let shouldTerminate = activeRequestID == requestID
        stateLock.unlock()
        if shouldTerminate {
            terminateOwnedProcess()
        }
    }

    private func isCancelled(_ requestID: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelledRequestIDs.contains(requestID)
    }

    private func terminateOwnedProcess() {
        stateLock.lock()
        let ownedProcess = process
        let ownedInput = inputHandle
        let ownedOutput = outputHandle
        let ownedErrorPipe = errorPipe
        process = nil
        inputHandle = nil
        outputHandle = nil
        errorPipe = nil
        stateLock.unlock()

        ownedErrorPipe?.fileHandleForReading.readabilityHandler = nil
        try? ownedInput?.close()
        try? ownedOutput?.close()

        guard let ownedProcess, ownedProcess.isRunning else { return }
        ownedProcess.terminate()
        let terminationDeadline = Date().addingTimeInterval(0.5)
        while ownedProcess.isRunning && Date() < terminationDeadline {
            usleep(10_000)
        }
        if ownedProcess.isRunning {
            kill(ownedProcess.processIdentifier, SIGKILL)
        }
    }
}
