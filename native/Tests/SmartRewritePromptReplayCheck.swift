import Foundation

private struct RewriteMeasurement: Codable {
    let text: String
    let ttftMilliseconds: Double
    let completionMilliseconds: Double
    let sourceCharacters: Int
    let outputCharacters: Int
    let compressionRatio: Double
    let failedChecks: [String]
}

private struct ReplayResult: Codable {
    let audioPath: String
    let asrText: String
    let asrSeconds: Double
    let normalizedText: String
    let observations: [String]
    let developerRequirement: RewriteMeasurement
    let exhaustiveSummary: RewriteMeasurement
}

private enum ReplayError: Error, LocalizedError {
    case invalidArguments
    case missingPath(String)
    case workerEnded(String)
    case invalidResponse(String)
    case workerFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: SmartRewritePromptReplayCheck --audio <wav> --repo-root <path> --output-dir <path>"
        case .missingPath(let path):
            return "missing_path: \(path)"
        case .workerEnded(let worker):
            return "worker_ended: \(worker)"
        case .invalidResponse(let detail):
            return "invalid_response: \(detail)"
        case .workerFailure(let detail):
            return "worker_failure: \(detail)"
        }
    }
}

private func replayNumeric(_ value: Any?) -> Double {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let value = value as? Double {
        return value
    }
    return 0
}

private final class JSONLineWorker {
    private let name: String
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var readBuffer = Data()

    init(name: String, executable: URL, script: URL) throws {
        self.name = name
        process.executableURL = executable
        process.arguments = [script.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
    }

    func request(_ payload: [String: Any]) throws -> [String: Any] {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
        let line = try readLine()
        guard let value = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ReplayError.invalidResponse("\(name) returned non-object JSON")
        }
        guard value["ok"] as? Bool == true else {
            let message = value["error_message"] as? String
                ?? value["error"] as? String
                ?? "unknown"
            throw ReplayError.workerFailure("\(name): \(message)")
        }
        return value
    }

    func stop() {
        input.fileHandleForWriting.closeFile()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func readLine() throws -> Data {
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer.prefix(upTo: newline)
                readBuffer.removeSubrange(...newline)
                return Data(line)
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                throw ReplayError.workerEnded(name)
            }
            readBuffer.append(chunk)
        }
    }
}

private final class ReplayRewriteEngine: SmartRewriteEngine {
    let displayName = "Replay Qwen3 4B"
    let logName = "replay_managed_mlx"
    let usesLocalCostGuard = false

    private let worker: JSONLineWorker
    private let modelDirectory: URL
    private(set) var lastGeneratedText = ""
    private(set) var lastTTFTMilliseconds = 0.0
    private(set) var lastCompletionMilliseconds = 0.0

    init(worker: JSONLineWorker, modelDirectory: URL) {
        self.worker = worker
        self.modelDirectory = modelDirectory
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        let prompt = SmartRewritePromptBuilder.prompt(
            rawText: rawText,
            mode: mode,
            context: context,
            preference: preference
        )
        let systemPrompt = SmartRewriteSafetyPrompt.rewriteSystemPrompt(
            lead: SmartRewriteSafetyPrompt.localRewriteLead
        )
        let response = try worker.request([
            "protocol_version": 1,
            "id": UUID().uuidString,
            "command": "rewrite",
            "model_directory": modelDirectory.path,
            "system_prompt": systemPrompt,
            "user_prompt": prompt,
            "reasoning": "low",
            "max_tokens": 1_024,
        ])
        guard let rawOutput = response["final_text"] as? String else {
            throw ReplayError.invalidResponse("LLM final_text is empty")
        }
        let metrics = response["metrics"] as? [String: Any] ?? [:]
        lastGeneratedText = SmartRewriteOutputSanitizer.cleanLocalModel(rawOutput)
        lastTTFTMilliseconds = replayNumeric(metrics["ttft_ms"])
        lastCompletionMilliseconds = replayNumeric(metrics["completion_ms"])
        return SmartRewriteEngineOutput(text: lastGeneratedText, usage: nil)
    }
}

@main
private struct SmartRewritePromptReplayCheck {
    static func main() async throws {
        let arguments = try parseArguments()
        let fileManager = FileManager.default
        let audioURL = URL(fileURLWithPath: arguments.audio)
        let repoRoot = URL(fileURLWithPath: arguments.repoRoot, isDirectory: true)
        let outputDirectory = URL(fileURLWithPath: arguments.outputDirectory, isDirectory: true)
        let home = fileManager.homeDirectoryForCurrentUser
        let runtime = home
            .appendingPathComponent("Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3")
        let asrWorkerURL = repoRoot.appendingPathComponent("native/Resources/mlx_asr_worker.py")
        let llmWorkerURL = repoRoot.appendingPathComponent("native/Resources/managed_mlx_llm_worker.py")
        let llmModelURL = home
            .appendingPathComponent("Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit")
        let asrRepository = home
            .appendingPathComponent(".cache/huggingface/hub/models--mlx-community--Qwen3-ASR-1.7B-8bit")
        let revisionURL = asrRepository.appendingPathComponent("refs/main")

        for url in [audioURL, runtime, asrWorkerURL, llmWorkerURL, llmModelURL, revisionURL] {
            guard fileManager.fileExists(atPath: url.path) else {
                throw ReplayError.missingPath(url.path)
            }
        }
        let revision = try String(contentsOf: revisionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let asrModelURL = asrRepository.appendingPathComponent("snapshots/\(revision)")
        guard fileManager.fileExists(atPath: asrModelURL.path) else {
            throw ReplayError.missingPath(asrModelURL.path)
        }

        let asrWorker = try JSONLineWorker(
            name: "qwen3-asr-1.7b",
            executable: runtime,
            script: asrWorkerURL
        )
        defer { asrWorker.stop() }
        _ = try asrWorker.request([
            "id": UUID().uuidString,
            "command": "warmup",
            "provider": "qwen3-asr-1.7b-mlx",
            "model_dir": asrModelURL.path,
        ])
        let asrResponse = try asrWorker.request([
            "id": UUID().uuidString,
            "command": "transcribe",
            "provider": "qwen3-asr-1.7b-mlx",
            "model_dir": asrModelURL.path,
            "audio_path": audioURL.path,
            "context_prompt": "",
        ])
        guard let asrText = asrResponse["text"] as? String,
              !asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplayError.invalidResponse("ASR text is empty")
        }
        let asrSeconds = numeric(asrResponse["duration_sec"])

        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        let normalization = DeveloperTermNormalizer().normalize(asrText, context: context)
        let normalizedText = normalization.text
        let llmWorker = try JSONLineWorker(
            name: "qwen3-4b-instruct",
            executable: runtime,
            script: llmWorkerURL
        )
        defer { llmWorker.stop() }
        _ = try llmWorker.request([
            "protocol_version": 1,
            "id": UUID().uuidString,
            "command": "warmup",
            "model_directory": llmModelURL.path,
            "system_prompt": "",
            "user_prompt": "",
            "reasoning": "low",
            "max_tokens": 8,
        ])

        let rewriteEngine = ReplayRewriteEngine(
            worker: llmWorker,
            modelDirectory: llmModelURL
        )
        let router = SmartInputRouter(engine: rewriteEngine)
        let developer = await rewrite(
            router: router,
            engine: rewriteEngine,
            source: asrText,
            normalizedSource: normalizedText,
            context: context,
            preference: .developerRequirement
        )
        let summary = await rewrite(
            router: router,
            engine: rewriteEngine,
            source: asrText,
            normalizedSource: normalizedText,
            context: context,
            preference: .exhaustiveSummary
        )
        var observations: [String] = []
        if normalizedText.contains("你不能保留我的疑问") {
            observations.append("asr_question_reversal_observed")
        }

        let result = ReplayResult(
            audioPath: audioURL.path,
            asrText: asrText,
            asrSeconds: asrSeconds,
            normalizedText: normalizedText,
            observations: observations,
            developerRequirement: developer,
            exhaustiveSummary: summary
        )
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(result)
        try jsonData.write(to: outputDirectory.appendingPathComponent("result.json"), options: .atomic)
        let markdown = renderMarkdown(result)
        try Data(markdown.utf8).write(
            to: outputDirectory.appendingPathComponent("result.md"),
            options: .atomic
        )
        print(outputDirectory.appendingPathComponent("result.md").path)

        if !developer.failedChecks.isEmpty || !summary.failedChecks.isEmpty {
            Foundation.exit(2)
        }
    }

    private static func rewrite(
        router: SmartInputRouter,
        engine: ReplayRewriteEngine,
        source: String,
        normalizedSource: String,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async -> RewriteMeasurement {
        let result = await router.rewrite(
            rawText: source,
            preference: preference,
            context: context
        )
        let text = result.text
        var failures = checks(for: text, mode: result.mode)
        if text != engine.lastGeneratedText || result.didFallback {
            failures.append("delivery_not_model_output")
        }
        return RewriteMeasurement(
            text: text,
            ttftMilliseconds: engine.lastTTFTMilliseconds,
            completionMilliseconds: engine.lastCompletionMilliseconds,
            sourceCharacters: normalizedSource.count,
            outputCharacters: text.count,
            compressionRatio: normalizedSource.isEmpty
                ? 0
                : Double(text.count) / Double(normalizedSource.count),
            failedChecks: failures
        )
    }

    private static func checks(for text: String, mode: RewriteMode) -> [String] {
        var failures: [String] = []
        let required: [(String, [String])] = [
            ("standalone_GPT", ["GPT"]),
            ("ChatGPT", ["ChatGPT"]),
            ("Codex", ["Codex"]),
            ("Xcode", ["Xcode"]),
            ("0.6B", ["0.6B", "零点六B", "零点六 B"]),
            ("1.7B", ["1.7B", "一点七B", "一点七 B"]),
            ("Qwen3_4B", ["Qwen3 4B", "Qwen 3 4B", "千问3 4B", "千问三 4B"]),
            ("Python", ["Python"]),
            ("SenseVoice", ["SenseVoice"]),
            ("next_Wednesday_3pm", ["下周三下午三点", "下周三下午 3 点", "下周三下午3点"]),
            ("not_today_3pm", ["不是今天下午三点", "不是今天下午 3 点", "非今天下午三点", "非今天下午 3 点"]),
            ("response_speed", ["响应速度"]),
            ("no_model_fallback", ["不要调用其他模型降级", "不调用其他模型降级", "不得调用其他模型降级", "禁止调用其他模型降级"]),
            ("no_sensevoice_fallback", ["不要因为某个模型失败", "模型失败也不要改用 SenseVoice", "失败后不要改用 SenseVoice", "不得因任一模型失败而改用SenseVoice", "不得因任一模型失败而改用 SenseVoice", "不因任一模型失败而改用SenseVoice", "不因任一模型失败而改用 SenseVoice", "禁止因任一模型失败而改用SenseVoice", "禁止因任一模型失败而改用 SenseVoice"]),
            ("no_new_technical_plan", ["不要扩写成一份新的技术方案", "不要扩写成新的技术方案", "不要把它扩写成一份新的技术方案", "不得扩写为新的技术方案", "不得扩写为技术方案", "不扩写为技术方案"]),
        ]
        for (name, alternatives) in required {
            if name == "standalone_GPT" {
                if !containsStandaloneASCII("GPT", in: text) {
                    failures.append(name)
                }
            } else if !alternatives.contains(where: text.contains) {
                failures.append(name)
            }
        }
        let orderedSteps: [(String, [String])] = [
            ("保存原始识别结果", ["保存原始识别结果"]),
            ("记录整理后的结果", ["记录整理后的结果", "记录整理后结果"]),
            ("比较两者", ["比较两者", "对比两者", "对比删减", "比较差异"]),
            ("决定是否修改提示词", ["决定是否修改提示词"]),
        ]
        var previous = text.startIndex
        for (name, alternatives) in orderedSteps {
            let ranges = alternatives.compactMap {
                text.range(of: $0, range: previous..<text.endIndex)
            }
            guard let range = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else {
                failures.append("ordered_step:\(name)")
                continue
            }
            previous = range.upperBound
        }
        if !text.contains("\n1.")
            && !text.contains("\n1、")
            && !text.contains("第一，") {
            failures.append("explicit_step_numbering")
        }
        if text.contains("用户要求") || text.contains("用户希望") {
            failures.append("third_person_rewrite")
        }
        if mode == .exhaustiveSummary,
           text.count >= 430 {
            failures.append("summary_not_compressed")
        }
        return failures
    }

    private static func containsStandaloneASCII(_ token: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: token, range: searchRange) {
            let before = range.lowerBound > text.startIndex
                ? text[text.index(before: range.lowerBound)]
                : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let beforeIsASCIIWord = before?.isASCIIWordCharacter ?? false
            let afterIsASCIIWord = after?.isASCIIWordCharacter ?? false
            if !beforeIsASCIIWord && !afterIsASCIIWord {
                return true
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func numeric(_ value: Any?) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        return 0
    }

    private static func renderMarkdown(_ result: ReplayResult) -> String {
        """
        # Smart Rewrite Prompt Replay

        ## Audio

        - Path: `\(result.audioPath)`
        - ASR seconds: \(format(result.asrSeconds))
        - Observations: \(result.observations.isEmpty ? "none" : result.observations.joined(separator: ", "))

        ## Raw ASR

        \(result.asrText)

        ## Normalized source

        \(result.normalizedText)

        ## 开发需求

        \(result.developerRequirement.text)

        - TTFT: \(format(result.developerRequirement.ttftMilliseconds)) ms
        - Completion: \(format(result.developerRequirement.completionMilliseconds)) ms
        - Characters: \(result.developerRequirement.outputCharacters) / \(result.developerRequirement.sourceCharacters)
        - Compression ratio: \(format(result.developerRequirement.compressionRatio))
        - Failed checks: \(result.developerRequirement.failedChecks.isEmpty ? "none" : result.developerRequirement.failedChecks.joined(separator: ", "))

        ## 极致归纳

        \(result.exhaustiveSummary.text)

        - TTFT: \(format(result.exhaustiveSummary.ttftMilliseconds)) ms
        - Completion: \(format(result.exhaustiveSummary.completionMilliseconds)) ms
        - Characters: \(result.exhaustiveSummary.outputCharacters) / \(result.exhaustiveSummary.sourceCharacters)
        - Compression ratio: \(format(result.exhaustiveSummary.compressionRatio))
        - Failed checks: \(result.exhaustiveSummary.failedChecks.isEmpty ? "none" : result.exhaustiveSummary.failedChecks.joined(separator: ", "))
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func parseArguments() throws -> (
        audio: String,
        repoRoot: String,
        outputDirectory: String
    ) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        guard let audio = value(after: "--audio"),
              let repoRoot = value(after: "--repo-root"),
              let outputDirectory = value(after: "--output-dir") else {
            throw ReplayError.invalidArguments
        }
        return (audio, repoRoot, outputDirectory)
    }
}

private extension Character {
    var isASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy(\.isASCII) && (isLetter || isNumber || self == "_")
    }
}
