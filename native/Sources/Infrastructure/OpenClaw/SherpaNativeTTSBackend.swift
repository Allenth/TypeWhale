import Foundation

final class SherpaNativeTTSBackend: OpenClawTTSBackend {
    private let executableURL: URL
    private let packDirectory: URL
    private let fileManager: FileManager
    private let processLock = NSLock()
    private var started = false
    private var activeProcess: Process?

    var isRunning: Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return started
    }

    init(executableURL: URL, packDirectory: URL, fileManager: FileManager = .default) {
        self.executableURL = executableURL
        self.packDirectory = packDirectory
        self.fileManager = fileManager
    }

    func start(timeoutSeconds: TimeInterval = 180) throws {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw OpenClawVoicePlaybackError.commandFailed("Missing native sherpa-onnx-offline-tts: \(executableURL.path)")
        }
        processLock.lock()
        started = true
        processLock.unlock()
    }

    func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval = 180) throws {
        let arguments = try Self.arguments(
            for: request,
            executableURL: executableURL,
            packDirectory: packDirectory
        )
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = OpenClawCommandClient.processEnvironment()

        processLock.lock()
        guard started else {
            processLock.unlock()
            throw OpenClawVoicePlaybackError.commandFailed("Sherpa native TTS is not running")
        }
        do {
            try process.run()
        } catch {
            processLock.unlock()
            throw OpenClawVoicePlaybackError.commandFailed(error.localizedDescription)
        }
        activeProcess = process
        processLock.unlock()
        defer { clearActiveProcess(process) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw OpenClawVoicePlaybackError.commandFailed(err.isEmpty ? out : err)
        }
        guard fileManager.fileExists(atPath: request.outputURL.path) else {
            throw OpenClawVoicePlaybackError.commandFailed("Sherpa native TTS did not create output WAV")
        }
    }

    func cancelSynthesis() {
        processLock.lock()
        let process = activeProcess
        processLock.unlock()
        process?.terminate()
    }

    func stop() {
        cancelSynthesis()
        processLock.lock()
        started = false
        processLock.unlock()
    }

    static func arguments(
        for request: OpenClawVoiceSynthesisRequest,
        executableURL: URL,
        packDirectory: URL
    ) throws -> [String] {
        let modelURL = modelURL(in: packDirectory)
        let lexiconURL = typewhaleLexiconURL(in: packDirectory)
            ?? packDirectory.appendingPathComponent("lexicon.txt")
        return [
            "--vits-model=\(modelURL.path)",
            "--vits-lexicon=\(lexiconURL.path)",
            "--vits-tokens=\(packDirectory.appendingPathComponent("tokens.txt").path)",
            "--vits-dict-dir=\(packDirectory.appendingPathComponent("dict", isDirectory: true).path)",
            "--num-threads=4",
            "--output-filename=\(request.outputURL.path)",
            request.speechText,
        ]
    }

    private static func modelURL(in packDirectory: URL) -> URL {
        let model = packDirectory.appendingPathComponent("model.onnx")
        if FileManager.default.fileExists(atPath: model.path) {
            return model
        }
        return packDirectory.appendingPathComponent("model.int8.onnx")
    }

    private static func typewhaleLexiconURL(in packDirectory: URL) -> URL? {
        let merged = packDirectory
            .appendingPathComponent(".typewhale", isDirectory: true)
            .appendingPathComponent("lexicon.typewhale.txt")
        return FileManager.default.fileExists(atPath: merged.path) ? merged : nil
    }

    private func clearActiveProcess(_ process: Process) {
        processLock.lock()
        if activeProcess === process {
            activeProcess = nil
        }
        processLock.unlock()
    }
}
