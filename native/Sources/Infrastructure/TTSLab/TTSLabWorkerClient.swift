import Foundation

enum TTSLabWorkerError: LocalizedError {
    case notRunning
    case closed(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "TTS worker 未运行"
        case .closed(let message):
            return message.isEmpty ? "TTS worker 已退出" : message
        case .protocolError(let message):
            return message
        }
    }
}

struct TTSLabSynthesisResult {
    let metrics: TTSLabMetrics
    let actualVoiceID: String
}

final class TTSLabWorkerClient {
    private struct Response: Decodable {
        struct Metrics: Decodable {
            let cold: Bool?
            let prepareSeconds: Double?
            let firstAudioSeconds: Double?
            let synthesisSeconds: Double?
            let audioSeconds: Double?
            let rtf: Double?
        }

        let id: String?
        let ok: Bool
        let phase: String
        let voiceID: String?
        let metrics: Metrics?
        let error: String?
    }

    private let pythonURL: URL
    private let workerURL: URL
    private let fakeDelay: Double?
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var prepareMetrics: Response.Metrics?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    init(pythonURL: URL, workerURL: URL, fakeDelay: Double? = nil) {
        self.pythonURL = pythonURL
        self.workerURL = workerURL
        self.fakeDelay = fakeDelay
    }

    func start(model: TTSLabModel) throws {
        stop()
        var arguments = [
            workerURL.path,
            "--engine", engineID(for: model),
        ]
        if model.id != "fake" {
            arguments += ["--pack", model.directory.path]
        }
        if let fakeDelay {
            arguments += ["--fake-delay", String(fakeDelay)]
        }
        try start(
            descriptor: TTSLabRuntimeDescriptor(
                adapterID: engineID(for: model),
                executableURL: pythonURL,
                arguments: arguments,
                environment: [
                    "HF_HUB_OFFLINE": "1",
                    "TRANSFORMERS_OFFLINE": "1",
                    "NO_PROXY": "*",
                ],
                fingerprint: "legacy-\(engineID(for: model))-v1"
            )
        )
    }

    func start(descriptor: TTSLabRuntimeDescriptor) throws {
        stop()
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = descriptor.executableURL
        process.arguments = descriptor.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            descriptor.environment
        ) { _, new in new }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        lock.lock()
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errorOutput = stderr.fileHandleForReading
        lock.unlock()
        let ready = try readResponse()
        guard ready.ok, ready.phase == "ready" else {
            throw TTSLabWorkerError.protocolError(ready.error ?? "TTS worker 启动失败")
        }
    }

    func health() throws {
        let response = try send(type: "health")
        guard response.phase == "healthy" else {
            throw TTSLabWorkerError.protocolError("TTS worker 健康检查失败")
        }
    }

    func prepare() throws -> (cold: Bool, seconds: Double) {
        let response = try send(type: "prepare")
        prepareMetrics = response.metrics
        return (
            response.metrics?.cold ?? true,
            response.metrics?.prepareSeconds ?? 0
        )
    }

    func synthesize(
        text: String,
        outputURL: URL,
        speakerID: Int = 0
    ) throws -> TTSLabMetrics {
        let response = try send(
            type: "synthesize",
            extra: [
                "text": text,
                "output": outputURL.path,
                "speakerID": speakerID,
            ]
        )
        return try metrics(from: response)
    }

    func synthesize(
        text: String,
        outputURL: URL,
        voice: TTSLabVoice,
        referenceDirectoryName: String? = nil
    ) throws -> TTSLabSynthesisResult {
        var extra: [String: Any] = [
            "text": text,
            "output": outputURL.path,
            "voiceID": voice.id,
        ]
        if let referenceDirectoryName {
            extra["referenceDirectoryName"] = referenceDirectoryName
        }
        let response = try send(
            type: "synthesize",
            extra: extra
        )
        guard response.voiceID == voice.id else {
            throw TTSLabWorkerError.protocolError("TTS worker 返回了错误的音色")
        }
        return TTSLabSynthesisResult(
            metrics: try metrics(from: response),
            actualVoiceID: voice.id
        )
    }

    private func metrics(from response: Response) throws -> TTSLabMetrics {
        guard let metrics = response.metrics else {
            throw TTSLabWorkerError.protocolError("TTS worker 未返回性能指标")
        }
        let audioSeconds = metrics.audioSeconds ?? 0
        let synthesisSeconds = metrics.synthesisSeconds ?? 0
        return TTSLabMetrics(
            cold: prepareMetrics?.cold ?? true,
            prepareSeconds: prepareMetrics?.prepareSeconds ?? 0,
            firstAudioSeconds: metrics.firstAudioSeconds ?? synthesisSeconds,
            synthesisSeconds: synthesisSeconds,
            audioSeconds: audioSeconds,
            rtf: metrics.rtf ?? synthesisSeconds / max(audioSeconds, 0.000_001),
            peakRSSBytes: currentRSSBytes()
        )
    }

    func shutdown() {
        if isRunning {
            _ = try? send(type: "shutdown")
        }
        stop()
    }

    func cancel() {
        stop()
    }

    func stop() {
        lock.lock()
        let process = self.process
        let input = self.input
        let output = self.output
        let errorOutput = self.errorOutput
        self.process = nil
        self.input = nil
        self.output = nil
        self.errorOutput = nil
        lock.unlock()
        input?.closeFile()
        output?.closeFile()
        errorOutput?.closeFile()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func send(type: String, extra: [String: Any] = [:]) throws -> Response {
        let requestID = UUID().uuidString
        var payload = extra
        payload["id"] = requestID
        payload["type"] = type
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let input else { throw TTSLabWorkerError.notRunning }
        try input.write(contentsOf: data + Data([0x0A]))
        let response = try readResponse()
        guard response.id == requestID else {
            throw TTSLabWorkerError.protocolError("TTS worker response id 不匹配")
        }
        guard response.ok else {
            throw TTSLabWorkerError.protocolError(response.error ?? "TTS worker 执行失败")
        }
        return response
    }

    private func readResponse() throws -> Response {
        guard let output else { throw TTSLabWorkerError.notRunning }
        var data = Data()
        while true {
            let chunk = try output.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                let message = errorOutput.flatMap {
                    try? $0.readToEnd()
                }.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
                throw TTSLabWorkerError.closed(message)
            }
            if chunk[0] == 0x0A { break }
            data.append(chunk)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func engineID(for model: TTSLabModel) -> String {
        switch model.id {
        case "fake": return "fake"
        case "zipvoice-distill-int8-zh-en-emilia": return "sherpa-zipvoice"
        default: return model.id
        }
    }

    private func currentRSSBytes() -> Int64 {
        lock.lock()
        let pid = process?.processIdentifier
        lock.unlock()
        guard let pid else { return 0 }
        let probe = Process()
        let pipe = Pipe()
        probe.executableURL = URL(fileURLWithPath: "/bin/ps")
        probe.arguments = ["-o", "rss=", "-p", String(pid)]
        probe.standardOutput = pipe
        try? probe.run()
        probe.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (Int64(text) ?? 0) * 1024
    }
}
