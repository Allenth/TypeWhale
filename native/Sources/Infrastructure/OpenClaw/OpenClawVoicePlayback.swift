import AVFoundation
import Foundation

enum OpenClawVoicePlaybackError: LocalizedError {
    case workerMissing
    case pythonMissing
    case modelMissing(String)
    case unsupportedModel(String)
    case commandFailed(String)
    case sidecarProtocol(String)

    var errorDescription: String? {
        switch self {
        case .workerMissing:
            return "找不到 OpenClaw TTS worker"
        case .pythonMissing:
            return "找不到本地 Python TTS 运行时"
        case .modelMissing(let path):
            return "找不到 TTS 模型：\(path)"
        case .unsupportedModel(let model):
            return "\(model) 暂未接入秒读朗读链路"
        case .commandFailed(let message):
            return message.isEmpty ? "OpenClaw 语音生成失败" : message
        case .sidecarProtocol(let message):
            return message.isEmpty ? "OpenClaw TTS sidecar 通信异常" : message
        }
    }
}

enum OpenClawVoicePlaybackNotification {
    static let didStartSpeaking = Notification.Name("TypeWhale.OpenClawVoice.didStartSpeaking")
    static let didStopSpeaking = Notification.Name("TypeWhale.OpenClawVoice.didStopSpeaking")
}

enum OpenClawVoiceRuntime {
    static let resourceName = "tts_benchmark_worker"
    static let resourceExtension = "py"

    static var defaultModelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhale Pro", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var defaultOutputDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeWhaleOpenClawVoice", isDirectory: true)
    }

    static func workerScriptURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }

    static func sidecarArguments(
        workerScriptURL: URL,
        engine: OpenClawVoiceEngine,
        packDirectory: URL
    ) -> [String] {
        [
            workerScriptURL.path,
            "--engine", "sherpa-zipvoice",
            "--pack", packDirectory.path,
        ]
    }

    static func speechText(from text: String, maxCharacters: Int = 1_200) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        result = replacingMatches(
            pattern: #"\[([^\]]+)\]\((https?://[^)]+)\)"#,
            in: result,
            template: "$1"
        )
        result = replacingMatches(pattern: #"(?m)^\s{0,3}#{1,6}\s*"#, in: result, template: "")
        result = replacingMatches(pattern: #"(?m)^\s{0,3}([-*_])(?:\s*\1){2,}\s*$"#, in: result, template: "")
        result = replacingMatches(pattern: #"\*\*([^*]+)\*\*"#, in: result, template: "$1")
        result = replacingMatches(pattern: #"`([^`]+)`"#, in: result, template: "$1")
        result = result
            .replacingOccurrences(of: "|---|", with: "")
            .replacingOccurrences(of: "---", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        let lines = result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let collapsed = lines.joined(separator: "\n")
        if collapsed.count <= maxCharacters {
            return collapsed
        }
        return String(collapsed.prefix(maxCharacters))
    }

    static func isSpeakable(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    static func speechSegments(
        from text: String,
        targetCharacters: Int = 60,
        maximumCharacters: Int = 100
    ) -> [String] {
        let readable = speechText(from: text)
        guard !readable.isEmpty else { return [] }
        let normalized = workerCompatibleText(readable)
        guard isSpeakable(normalized) else { return [] }
        if normalized.count <= maximumCharacters {
            return [normalized]
        }

        let sentenceEndings = CharacterSet(charactersIn: "。！？!?；;")
        var sentences: [String] = []
        var sentence = ""
        for scalar in normalized.unicodeScalars {
            sentence.unicodeScalars.append(scalar)
            if sentenceEndings.contains(scalar) {
                appendSpeakableChunks(
                    sentence,
                    maximumCharacters: maximumCharacters,
                    to: &sentences
                )
                sentence = ""
            }
        }
        appendSpeakableChunks(
            sentence,
            maximumCharacters: maximumCharacters,
            to: &sentences
        )

        var segments: [String] = []
        var current = ""
        for next in sentences {
            if current.isEmpty {
                current = next
            } else if current.count >= targetCharacters
                        || current.count + next.count > maximumCharacters {
                segments.append(current)
                current = next
            } else {
                current += next
            }
        }
        if !current.isEmpty {
            if current.count < 40,
               let last = segments.last,
               last.count + current.count <= maximumCharacters {
                segments[segments.count - 1] = last + current
            } else {
                segments.append(current)
            }
        }
        return segments.filter(isSpeakable)
    }

    private static func workerCompatibleText(_ text: String) -> String {
        let quoteCharacters = CharacterSet(charactersIn: "\"“”'‘’`")
        var normalized = ""
        var previousWasLineBreak = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                previousWasLineBreak = true
                continue
            }
            if quoteCharacters.contains(scalar)
                || scalar.properties.generalCategory == .otherSymbol
                || (0xFE00...0xFE0F).contains(scalar.value) {
                continue
            }
            if previousWasLineBreak,
               !normalized.isEmpty,
               let last = normalized.unicodeScalars.last,
               !CharacterSet(charactersIn: "。！？!?；;，,").contains(last) {
                normalized.append("，")
            }
            previousWasLineBreak = false
            normalized.unicodeScalars.append(scalar)
        }
        return normalized
            .replacingOccurrences(of: "——", with: "，")
            .replacingOccurrences(of: "—", with: "，")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendSpeakableChunks(
        _ rawText: String,
        maximumCharacters: Int,
        to chunks: inout [String]
    ) {
        var remaining = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSpeakable(remaining) else { return }
        while remaining.count > maximumCharacters {
            let hardEnd = remaining.index(remaining.startIndex, offsetBy: maximumCharacters)
            let prefix = remaining[..<hardEnd]
            let preferred = prefix.lastIndex(where: { "，,、：:".contains($0) })
            let split = preferred.map { remaining.index(after: $0) } ?? hardEnd
            let chunk = String(remaining[..<split])
            if isSpeakable(chunk) {
                chunks.append(chunk)
            }
            remaining = String(remaining[split...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isSpeakable(remaining) {
            chunks.append(remaining)
        }
    }

    private static func replacingMatches(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

struct OpenClawVoiceSynthesisRequest: Equatable {
    let text: String
    let settings: OpenClawVoiceSettings
    let workerScriptURL: URL?
    let modelsRoot: URL
    let outputURL: URL

    var speechText: String {
        OpenClawVoiceRuntime.speechText(from: text)
    }

    var packDirectory: URL {
        modelsRoot.appendingPathComponent(settings.engine.relativeDirectory, isDirectory: true)
    }
}

final class OpenClawVoicePlayer {
    static let shared = OpenClawVoicePlayer()

    private let stateQueue = DispatchQueue(label: "com.typewhale.openclaw.voice.player", qos: .utility)
    private let workerQueue = DispatchQueue(label: "com.typewhale.openclaw.voice.worker", qos: .utility)
    private let processLock = NSLock()
    private var pending: [OpenClawVoiceSynthesisRequest] = []
    private var isRunning = false
    private var activeAudioPlayer: AVAudioPlayer?
    private var activeBackend: OpenClawTTSBackend?
    private var activeBackendEngine: OpenClawVoiceEngine?
    private var activeBackendPackDirectory: URL?
    private var backendGeneration = 0
    private var idleShutdownWorkItem: DispatchWorkItem?

    func prewarm(settings: OpenClawVoiceSettings = OpenClawVoiceSettingsStore.standard.load()) {
        let normalized = settings.normalized
        guard normalized.enabled, normalized.playbackPolicy == .finalReplyOnly else { return }
        workerQueue.async {
            do {
                let startedAt = Date()
                _ = try self.ensureBackend(settings: normalized)
                LaunchDiagnostics.mark(
                    "openclaw_voice_prewarm_done engine=\(normalized.engine.rawValue) seconds=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
                )
                self.scheduleBackendIdleShutdown()
            } catch {
                LaunchDiagnostics.mark("openclaw_voice_prewarm_failed error=\"\(error.localizedDescription)\"")
            }
        }
    }

    func speak(_ text: String, settings: OpenClawVoiceSettings = OpenClawVoiceSettingsStore.standard.load()) {
        let normalized = settings.normalized
        guard normalized.enabled, normalized.playbackPolicy == .finalReplyOnly else { return }
        let requests = OpenClawVoiceRuntime.speechSegments(from: text).compactMap {
            makeRequest(text: $0, settings: normalized)
        }
        guard !requests.isEmpty else { return }

        switch normalized.interruptPolicy {
        case .stopPreviousAndPlayLatest:
            stopActiveAudioPlayback()
            cancelActiveSynthesis()
            stateQueue.async {
                self.pending.removeAll()
                self.pending.append(contentsOf: requests)
                self.startIfNeeded()
            }
        case .queueReplies:
            stateQueue.async {
                self.pending.append(contentsOf: requests)
                self.startIfNeeded()
            }
        case .doNotInterrupt:
            stateQueue.async {
                guard !self.isRunning, self.pending.isEmpty else { return }
                self.pending.append(contentsOf: requests)
                self.startIfNeeded()
            }
        }
    }

    func stop() {
        stateQueue.sync {
            self.pending.removeAll()
        }
        stopActiveProcesses()
    }

    private func makeRequest(
        text: String,
        settings: OpenClawVoiceSettings
    ) -> OpenClawVoiceSynthesisRequest? {
        let outputDirectory = OpenClawVoiceRuntime.defaultOutputDirectory
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory
            .appendingPathComponent("openclaw-\(UUID().uuidString).wav")
        let request = OpenClawVoiceSynthesisRequest(
            text: text,
            settings: settings,
            workerScriptURL: OpenClawVoiceRuntime.workerScriptURL(),
            modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot,
            outputURL: outputURL
        )
        guard !request.speechText.isEmpty else {
            LaunchDiagnostics.mark("openclaw_voice_skip reason=empty_speech_text")
            return nil
        }
        return request
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
        workerQueue.async {
            self.processQueue()
        }
    }

    private func processQueue() {
        while true {
            let request = stateQueue.sync { () -> OpenClawVoiceSynthesisRequest? in
                guard !pending.isEmpty else {
                    isRunning = false
                    return nil
                }
                return pending.removeFirst()
            }
            guard let request else { return }
            do {
                var current: (request: OpenClawVoiceSynthesisRequest, synthSeconds: TimeInterval)? = try synthesizeTimed(request)
                while let item = current {
                    var prefetched: (request: OpenClawVoiceSynthesisRequest, synthSeconds: TimeInterval)?
                    let bufferWaitSeconds = try play(
                        item.request.outputURL,
                        settings: item.request.settings,
                        duringPlayback: {
                            prefetched = self.synthesizeNextPendingRequest()
                    })
                    try? FileManager.default.removeItem(at: item.request.outputURL)
                    LaunchDiagnostics.mark(
                        "openclaw_voice_played engine=\(item.request.settings.engine.rawValue) chars=\(item.request.speechText.count) synth_seconds=\(String(format: "%.3f", item.synthSeconds)) buffer_wait_seconds=\(String(format: "%.3f", bufferWaitSeconds))"
                    )
                    current = prefetched
                }
                scheduleBackendIdleShutdown()
            } catch {
                LaunchDiagnostics.mark("openclaw_voice_failed error=\"\(error.localizedDescription)\"")
                scheduleBackendIdleShutdown()
            }
        }
    }

    private func synthesizeNextPendingRequest()
        -> (request: OpenClawVoiceSynthesisRequest, synthSeconds: TimeInterval)?
    {
        while let request = stateQueue.sync(execute: {
            pending.isEmpty ? nil : pending.removeFirst()
        }) {
            do {
                return try synthesizeTimed(request)
            } catch {
                try? FileManager.default.removeItem(at: request.outputURL)
                LaunchDiagnostics.mark(
                    "openclaw_voice_failed stage=prefetch error=\"\(error.localizedDescription)\""
                )
            }
        }
        return nil
    }

    private func synthesizeTimed(_ request: OpenClawVoiceSynthesisRequest) throws -> (request: OpenClawVoiceSynthesisRequest, synthSeconds: TimeInterval) {
        let startedAt = Date()
        try synthesize(request)
        return (request, Date().timeIntervalSince(startedAt))
    }

    private func synthesize(_ request: OpenClawVoiceSynthesisRequest) throws {
        let backend = try ensureBackend(settings: request.settings)
        try backend.synthesize(request, timeoutSeconds: 180)
    }

    private func ensureBackend(settings: OpenClawVoiceSettings) throws -> OpenClawTTSBackend {
        let probeRequest = OpenClawVoiceSynthesisRequest(
            text: "warmup",
            settings: settings,
            workerScriptURL: OpenClawVoiceRuntime.workerScriptURL(),
            modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot,
            outputURL: OpenClawVoiceRuntime.defaultOutputDirectory.appendingPathComponent("warmup.wav")
        )
        processLock.lock()
        if let activeBackend,
           activeBackendEngine == settings.engine,
           activeBackendPackDirectory == probeRequest.packDirectory,
           activeBackend.isRunning {
            processLock.unlock()
            return activeBackend
        }
        let previousBackend = activeBackend
        activeBackend = nil
        activeBackendEngine = nil
        activeBackendPackDirectory = nil
        let generation = backendGeneration
        processLock.unlock()
        previousBackend?.stop()

        guard settings.engine == .zipVoice,
              let workerURL = probeRequest.workerScriptURL else {
            throw OpenClawVoicePlaybackError.workerMissing
        }
        let pythonURL = URL(fileURLWithPath: "/usr/local/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw OpenClawVoicePlaybackError.pythonMissing
        }
        for requiredPath in [
            "encoder.int8.onnx",
            "decoder.int8.onnx",
            "vocos_24khz.onnx",
            "tokens.txt",
            "lexicon.txt",
            "LICENSE",
            "references/\(settings.voiceID)/reference.json",
        ] {
            guard FileManager.default.fileExists(
                atPath: probeRequest.packDirectory
                    .appendingPathComponent(requiredPath)
                    .path
            ) else {
                throw OpenClawVoicePlaybackError.modelMissing(
                    probeRequest.packDirectory.path
                )
            }
        }
        let next: OpenClawTTSBackend = ZipVoiceTTSBackend(
            pythonURL: pythonURL,
            workerScriptURL: workerURL,
            packDirectory: probeRequest.packDirectory
        )
        try next.start(timeoutSeconds: 180)
        processLock.lock()
        guard backendGeneration == generation else {
            processLock.unlock()
            next.stop()
            throw OpenClawVoicePlaybackError.commandFailed("OpenClaw 朗读已取消")
        }
        activeBackend = next
        activeBackendEngine = settings.engine
        activeBackendPackDirectory = probeRequest.packDirectory
        processLock.unlock()
        scheduleBackendIdleShutdown()
        return next
    }

    private func scheduleBackendIdleShutdown() {
        idleShutdownWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let idle = self.stateQueue.sync { !self.isRunning && self.pending.isEmpty }
            guard idle else { self.scheduleBackendIdleShutdown(); return }
            self.processLock.lock()
            let backend = self.activeBackend
            self.activeBackend = nil
            self.activeBackendEngine = nil
            self.activeBackendPackDirectory = nil
            self.processLock.unlock()
            backend?.stop()
            LaunchDiagnostics.mark("openclaw_voice_idle_release engine=any seconds=180")
        }
        idleShutdownWorkItem = item
        workerQueue.asyncAfter(deadline: .now() + 180, execute: item)
    }

    private func play(
        _ fileURL: URL,
        settings: OpenClawVoiceSettings,
        duringPlayback: () -> Void = {}
    ) throws -> TimeInterval {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.enableRate = true
        player.rate = Float(settings.speechRate)
        player.volume = Float(settings.volume)
        player.prepareToPlay()
        processLock.lock()
        activeAudioPlayer = player
        processLock.unlock()
        player.play()
        let playbackStartedAt = Date()
        let effectiveDuration = player.duration / max(settings.speechRate, 0.01)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: OpenClawVoicePlaybackNotification.didStartSpeaking, object: nil)
        }
        duringPlayback()
        let bufferWaitSeconds = max(
            0,
            Date().timeIntervalSince(playbackStartedAt) - effectiveDuration
        )
        while player.isPlaying {
            Thread.sleep(forTimeInterval: 0.05)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: OpenClawVoicePlaybackNotification.didStopSpeaking, object: nil)
        }
        processLock.lock()
        if activeAudioPlayer === player {
            activeAudioPlayer = nil
        }
        processLock.unlock()
        return bufferWaitSeconds
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        processKeyPath: ReferenceWritableKeyPath<OpenClawVoicePlayer, Process?>,
        timeoutSeconds: TimeInterval
    ) throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = OpenClawCommandClient.processEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr

        processLock.lock()
        self[keyPath: processKeyPath] = process
        processLock.unlock()

        do {
            try process.run()
        } catch {
            clearActiveProcess(process, keyPath: processKeyPath)
            throw OpenClawVoicePlaybackError.commandFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        clearActiveProcess(process, keyPath: processKeyPath)

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw OpenClawVoicePlaybackError.commandFailed(err.isEmpty ? out : err)
        }
    }

    private func clearActiveProcess(
        _ process: Process,
        keyPath: ReferenceWritableKeyPath<OpenClawVoicePlayer, Process?>
    ) {
        processLock.lock()
        if self[keyPath: keyPath] === process {
            self[keyPath: keyPath] = nil
        }
        processLock.unlock()
    }

    private func stopActiveProcesses() {
        idleShutdownWorkItem?.cancel()
        processLock.lock()
        let player = activeAudioPlayer
        let backend = activeBackend
        activeAudioPlayer = nil
        activeBackend = nil
        activeBackendEngine = nil
        activeBackendPackDirectory = nil
        backendGeneration &+= 1
        processLock.unlock()
        player?.stop()
        backend?.stop()
    }

    private func stopActiveAudioPlayback() {
        processLock.lock()
        let player = activeAudioPlayer
        activeAudioPlayer = nil
        processLock.unlock()
        player?.stop()
    }

    private func cancelActiveSynthesis() {
        processLock.lock()
        let backend = activeBackend
        processLock.unlock()
        backend?.cancelSynthesis()
    }
}

final class ZipVoiceTTSBackend: OpenClawTTSBackend {
    private let pythonURL: URL
    private let workerScriptURL: URL
    private let packDirectory: URL
    private let outputLock = NSLock()
    private let lineSemaphore = DispatchSemaphore(value: 0)
    private let stdoutQueue = DispatchQueue(label: "com.typewhale.openclaw.voice.stdout", qos: .utility)
    private let stderrQueue = DispatchQueue(label: "com.typewhale.openclaw.voice.stderr", qos: .utility)
    private var stdoutBuffer = Data()
    private var stdoutLines: [String] = []
    private var stderrBuffer = Data()
    private var stdoutClosed = false
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutReadHandle: FileHandle?
    private var stderrReadHandle: FileHandle?

    var isRunning: Bool {
        process?.isRunning == true
    }

    init(pythonURL: URL, workerScriptURL: URL, packDirectory: URL) {
        self.pythonURL = pythonURL
        self.workerScriptURL = workerScriptURL
        self.packDirectory = packDirectory
    }

    func start(timeoutSeconds: TimeInterval = 180) throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = pythonURL
        process.arguments = OpenClawVoiceRuntime.sidecarArguments(
            workerScriptURL: workerScriptURL,
            engine: .zipVoice,
            packDirectory: packDirectory
        )
        process.environment = OpenClawCommandClient.processEnvironment()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdoutReadHandle = stdout.fileHandleForReading
        stderrReadHandle = stderr.fileHandleForReading
        outputLock.lock()
        stdoutClosed = false
        outputLock.unlock()

        stdoutQueue.async { [weak self, handle = stdout.fileHandleForReading] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else {
                    self?.markPipeClosed()
                    return
                }
                self?.appendStdout(data)
            }
        }
        stderrQueue.async { [weak self, handle = stderr.fileHandleForReading] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.appendStderr(data)
            }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        let ready = try readLine(timeoutSeconds: timeoutSeconds)
        let response = try parseResponse(ready)
        guard response.ok else {
            throw OpenClawVoicePlaybackError.sidecarProtocol(response.error ?? "sidecar failed to start")
        }
        try send(
            type: "prepare",
            output: nil,
            text: nil,
            voiceID: nil,
            timeoutSeconds: timeoutSeconds
        )
    }

    func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval = 180) throws {
        try send(
            type: "synthesize",
            output: request.outputURL.path,
            text: request.speechText,
            voiceID: request.settings.voiceID,
            timeoutSeconds: timeoutSeconds
        )
    }

    func cancelSynthesis() {
        stop()
    }

    private func send(
        type: String,
        output: String?,
        text: String?,
        voiceID: String?,
        timeoutSeconds: TimeInterval
    ) throws {
        let requestID = UUID().uuidString
        var payload: [String: Any] = ["id": requestID, "type": type]
        if let output { payload["output"] = output }
        if let text { payload["text"] = text }
        if let voiceID { payload["voiceID"] = voiceID }
        try write(payload)
        let line = try readLine(timeoutSeconds: timeoutSeconds)
        let response = try parseResponse(line)
        guard response.id == requestID else {
            throw OpenClawVoicePlaybackError.sidecarProtocol("ZipVoice response id mismatch")
        }
        guard response.ok else {
            throw OpenClawVoicePlaybackError.commandFailed(response.error ?? "ZipVoice command failed")
        }
        if type == "synthesize", response.voiceID != voiceID {
            throw OpenClawVoicePlaybackError.sidecarProtocol(
                "ZipVoice 返回了错误的音色"
            )
        }
    }

    func stop() {
        process?.terminate()
        stdinHandle?.closeFile()
        stdoutReadHandle?.closeFile()
        stderrReadHandle?.closeFile()
        process = nil
        stdinHandle = nil
        stdoutReadHandle = nil
        stderrReadHandle = nil
    }

    private func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let handle = stdinHandle else {
            throw OpenClawVoicePlaybackError.sidecarProtocol("sidecar stdin is closed")
        }
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    private func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        outputLock.lock()
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                stdoutLines.append(line)
                lineSemaphore.signal()
            }
        }
        outputLock.unlock()
    }

    private func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        outputLock.lock()
        stderrBuffer.append(data)
        outputLock.unlock()
    }

    private func markPipeClosed() {
        outputLock.lock()
        stdoutClosed = true
        outputLock.unlock()
        lineSemaphore.signal()
    }

    private func readLine(timeoutSeconds: TimeInterval) throws -> String {
        let deadline = DispatchTime.now() + timeoutSeconds
        while true {
            outputLock.lock()
            if !stdoutLines.isEmpty {
                let line = stdoutLines.removeFirst()
                outputLock.unlock()
                return line
            }
            if stdoutClosed {
                outputLock.unlock()
                throw OpenClawVoicePlaybackError.sidecarProtocol("ZipVoice sidecar closed its output pipe")
            }
            outputLock.unlock()
            if lineSemaphore.wait(timeout: deadline) == .timedOut {
                throw OpenClawVoicePlaybackError.commandFailed(currentStderr())
            }
        }
    }

    private func currentStderr() -> String {
        outputLock.lock()
        let data = stderrBuffer
        outputLock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private struct SidecarResponse {
        let ok: Bool
        let id: String?
        let voiceID: String?
        let error: String?
    }

    private func parseResponse(_ line: String) throws -> SidecarResponse {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenClawVoicePlaybackError.sidecarProtocol(line)
        }
        return SidecarResponse(
            ok: (object["ok"] as? Bool) == true,
            id: object["id"] as? String,
            voiceID: object["voiceID"] as? String,
            error: object["error"] as? String
        )
    }
}
