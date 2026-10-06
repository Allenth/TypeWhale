import Darwin
import Foundation

struct MLXASRTranscriptionResult: Equatable {
    let text: String; let engine: String; let durationSeconds: Double; let hotwordStrategy: String
}

final class MLXASRSidecar: @unchecked Sendable {
    private let pythonURL: URL, workerURL: URL, requestTimeout: TimeInterval
    private let queue = DispatchQueue(label: "com.waykingah.typewhale.mlx-asr-sidecar", qos: .userInitiated)
    private var process: Process?; private var input: FileHandle?; private var output: FileHandle?; private var errorPipe: Pipe?
    private var loadedProvider: String?
    init(pythonURL: URL, workerURL: URL, requestTimeout: TimeInterval = 180) { self.pythonURL=pythonURL; self.workerURL=workerURL; self.requestTimeout=requestTimeout }
    deinit { stopOnQueue() }

    func warmUp(providerID: String, modelDirectory: URL, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in guard let self else { return }; do {
            if loadedProvider != nil && loadedProvider != providerID { stopOnQueue() }
            let response = try send(.init(id: UUID().uuidString, command: .warmup, provider: providerID, modelDirectory: modelDirectory.path))
            guard response.ok else { throw failure(response.error ?? "MLX 预热失败") }
            loadedProvider = providerID; completion(.success(response.engine ?? "\(providerID)/mlx"))
        } catch { stopOnQueue(); completion(.failure(error)) } }
    }
    func transcribe(providerID: String, audioURL: URL, contextPrompt: String?, completion: @escaping (Result<MLXASRTranscriptionResult, Error>) -> Void) {
        queue.async { [weak self] in guard let self else { return }; do {
            guard loadedProvider == providerID else { throw failure("MLX 模型尚未预热") }
            let response = try send(.init(id: UUID().uuidString, command: .transcribe, provider: providerID, audioPath: audioURL.path, contextPrompt: contextPrompt))
            guard response.ok else { throw failure(response.error ?? "MLX 识别失败") }
            let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw failure("MLX 返回空文本") }
            completion(.success(.init(text: text, engine: response.engine ?? "\(providerID)/mlx", durationSeconds: response.durationSeconds ?? 0, hotwordStrategy: response.hotwordStrategy ?? "none")))
        } catch { stopOnQueue(); completion(.failure(error)) } }
    }
    func stop() { queue.sync { stopOnQueue() } }

    private func ensureProcess() throws {
        if let process, process.isRunning, input != nil, output != nil { return }
        stopOnQueue(); let p=Process(), i=Pipe(), o=Pipe(), e=Pipe(); p.executableURL=pythonURL; p.arguments=[workerURL.path]
        p.environment = ProcessInfo.processInfo.environment.merging(["HF_HUB_OFFLINE":"1", "TRANSFORMERS_OFFLINE":"1", "HF_DATASETS_OFFLINE":"1"]) { _, new in new }
        p.standardInput=i; p.standardOutput=o; p.standardError=e
        e.fileHandleForReading.readabilityHandler = { h in let d=h.availableData; if !d.isEmpty { _ = String(data:d,encoding:.utf8) } }
        try p.run(); process=p; input=i.fileHandleForWriting; output=o.fileHandleForReading; errorPipe=e
    }
    private func send(_ request: MLXASRSidecarRequest) throws -> MLXASRSidecarResponse {
        try ensureProcess(); guard let input, let output else { throw failure("MLX sidecar 管道不可用") }
        var data=try JSONEncoder().encode(request); data.append(0x0a); try input.write(contentsOf:data)
        let response=try JSONDecoder().decode(MLXASRSidecarResponse.self, from: readLine(output)); guard response.id == request.id else { throw failure("MLX response id mismatch") }; return response
    }
    private func readLine(_ handle: FileHandle) throws -> Data {
        let deadline=Date().addingTimeInterval(requestTimeout); var data=Data()
        while data.count < 1_048_576 {
            let remaining=deadline.timeIntervalSinceNow; guard remaining > 0 else { throw failure("MLX 识别超时") }
            var fd=pollfd(fd:handle.fileDescriptor,events:Int16(POLLIN),revents:0); let r=Darwin.poll(&fd,1,Int32(max(1,remaining*1000)))
            if r == 0 { throw failure("MLX 识别超时") }; if r < 0 { if errno == EINTR { continue }; throw failure("MLX sidecar 读取失败") }
            var byte:UInt8=0; guard Darwin.read(handle.fileDescriptor,&byte,1)==1 else { throw failure("MLX sidecar 已退出") }; if byte==0x0a { return data }; data.append(byte)
        }
        throw failure("MLX sidecar 响应过大")
    }
    private func stopOnQueue() {
        errorPipe?.fileHandleForReading.readabilityHandler=nil; try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate(); let end=Date().addingTimeInterval(0.5); while process.isRunning && Date()<end { usleep(10_000) }; if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
        process=nil; input=nil; output=nil; errorPipe=nil; loadedProvider=nil
    }
    private func failure(_ message:String)->NSError { NSError(domain:"com.waykingah.typewhale.mlx-asr-sidecar",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
