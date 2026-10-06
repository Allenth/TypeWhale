import Foundation
import Darwin

private func replayNumeric(_ value: Any?) -> Double {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let number = value as? Double {
        return number
    }
    return 0
}

private struct RewriteReplayCase {
    let id: String
    let mode: RewriteMode
    let preference: SmartRewritePreference
    let source: String
    let requiredAll: [String]
    let requiredAny: [[String]]
    let forbidden: [String]
    let mustRemainQuestion: Bool
    let mustDifferFromSource: Bool
    let minimumListItems: Int
    let maximumListItems: Int?

    init(
        id: String,
        mode: RewriteMode,
        preference: SmartRewritePreference,
        source: String,
        requiredAll: [String],
        requiredAny: [[String]],
        forbidden: [String],
        mustRemainQuestion: Bool,
        mustDifferFromSource: Bool = false,
        minimumListItems: Int = 0,
        maximumListItems: Int? = nil
    ) {
        self.id = id
        self.mode = mode
        self.preference = preference
        self.source = source
        self.requiredAll = requiredAll
        self.requiredAny = requiredAny
        self.forbidden = forbidden
        self.mustRemainQuestion = mustRemainQuestion
        self.mustDifferFromSource = mustDifferFromSource
        self.minimumListItems = minimumListItems
        self.maximumListItems = maximumListItems
    }
}

private struct RewriteReplayMeasurement: Codable {
    let round: Int
    let caseID: String
    let mode: String
    let source: String
    let output: String
    let ttftMilliseconds: Double
    let completionMilliseconds: Double
    let failedChecks: [String]
}

private struct RewriteReplayReport: Codable {
    let model: String
    let rounds: Int
    let generatedAt: String
    let measurements: [RewriteReplayMeasurement]
}

private enum RewriteReplayError: Error, LocalizedError {
    case invalidArguments
    case missingPath(String)
    case invalidResponse(String)
    case workerEnded
    case workerFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: AllRewriteModesSemanticReplayCheck --repo-root <path> --output-dir <path> --rounds <count>"
        case .missingPath(let path):
            return "missing_path: \(path)"
        case .invalidResponse(let detail):
            return "invalid_response: \(detail)"
        case .workerEnded:
            return "managed_mlx_worker_ended"
        case .workerFailure(let detail):
            return "managed_mlx_worker_failure: \(detail)"
        }
    }
}

private final class RewriteJSONLineWorker {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var readBuffer = Data()

    init(executable: URL, script: URL) throws {
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
        guard let value = try JSONSerialization.jsonObject(with: line)
            as? [String: Any] else {
            throw RewriteReplayError.invalidResponse(
                "worker returned non-object JSON"
            )
        }
        guard value["ok"] as? Bool == true else {
            let message = value["error_message"] as? String
                ?? value["error"] as? String
                ?? "unknown"
            throw RewriteReplayError.workerFailure(message)
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
                throw RewriteReplayError.workerEnded
            }
            readBuffer.append(chunk)
        }
    }
}

private final class AllModesReplayEngine {
    let displayName = "Qwen3 4B Instruct"

    private let worker: RewriteJSONLineWorker
    private let modelDirectory: URL
    private(set) var ttftMilliseconds = 0.0
    private(set) var completionMilliseconds = 0.0

    init(worker: RewriteJSONLineWorker, modelDirectory: URL) {
        self.worker = worker
        self.modelDirectory = modelDirectory
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) throws -> String {
        let response = try worker.request([
            "protocol_version": 1,
            "id": UUID().uuidString,
            "command": "rewrite",
            "model_directory": modelDirectory.path,
            "system_prompt": SmartRewriteSafetyPrompt.rewriteSystemPrompt(
                lead: SmartRewriteSafetyPrompt.localRewriteLead
            ),
            "user_prompt": SmartRewritePromptBuilder.prompt(
                rawText: rawText,
                mode: mode,
                context: context,
                preference: preference
            ),
            "reasoning": "low",
            "max_tokens": 768,
        ])
        guard let rawOutput = response["final_text"] as? String else {
            throw RewriteReplayError.invalidResponse("final_text is missing")
        }
        let metrics = response["metrics"] as? [String: Any] ?? [:]
        ttftMilliseconds = replayNumeric(metrics["ttft_ms"])
        completionMilliseconds = replayNumeric(metrics["completion_ms"])
        let cleaned = SmartRewriteOutputSanitizer.cleanLocalModel(rawOutput)
        return SmartRewriteOutputSanitizer.finalize(cleaned, mode: mode)
    }
}

@main
private enum AllRewriteModesSemanticReplayCheck {
    static func main() {
        do {
            try run()
        } catch {
            fputs("semantic_replay_failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let arguments = try parseArguments()
        let repository = URL(
            fileURLWithPath: arguments.repository,
            isDirectory: true
        )
        let outputDirectory = URL(
            fileURLWithPath: arguments.outputDirectory,
            isDirectory: true
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtime = home.appendingPathComponent(
            "Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3"
        )
        let workerScript = repository.appendingPathComponent(
            "native/Resources/managed_mlx_llm_worker.py"
        )
        let modelDirectory = home.appendingPathComponent(
            "Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit"
        )
        for url in [runtime, workerScript, modelDirectory] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw RewriteReplayError.missingPath(url.path)
            }
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let worker = try RewriteJSONLineWorker(
            executable: runtime,
            script: workerScript
        )
        defer { worker.stop() }
        _ = try worker.request([
            "protocol_version": 1,
            "id": UUID().uuidString,
            "command": "warmup",
            "model_directory": modelDirectory.path,
            "system_prompt": "",
            "user_prompt": "",
            "reasoning": "low",
            "max_tokens": 8,
        ])

        let engine = AllModesReplayEngine(
            worker: worker,
            modelDirectory: modelDirectory
        )
        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        var measurements: [RewriteReplayMeasurement] = []
        for round in 1...arguments.rounds {
            for replayCase in cases {
                let output = try engine.rewrite(
                    rawText: replayCase.source,
                    mode: replayCase.mode,
                    context: context,
                    preference: replayCase.preference
                )
                measurements.append(
                    RewriteReplayMeasurement(
                        round: round,
                        caseID: replayCase.id,
                        mode: replayCase.mode.rawValue,
                        source: replayCase.source,
                        output: output,
                        ttftMilliseconds: engine.ttftMilliseconds,
                        completionMilliseconds: engine.completionMilliseconds,
                        failedChecks: failures(
                            for: replayCase,
                            output: output
                        )
                    )
                )
            }
        }

        let report = RewriteReplayReport(
            model: engine.displayName,
            rounds: arguments.rounds,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            measurements: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        try encoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("result.json"),
            options: .atomic
        )
        let markdown = renderMarkdown(report)
        try markdown.write(
            to: outputDirectory.appendingPathComponent("result.md"),
            atomically: true,
            encoding: .utf8
        )
        print(outputDirectory.appendingPathComponent("result.md").path)

        let failed = measurements.filter { !$0.failedChecks.isEmpty }
        guard failed.isEmpty else {
            let details = failed.map {
                "round=\($0.round) mode=\($0.mode) case=\($0.caseID) failures=\($0.failedChecks.joined(separator: ","))"
            }
            throw RewriteReplayError.invalidResponse(
                details.joined(separator: "; ")
            )
        }
    }

    private static let question = "这个模型为什么突然变慢了？"

    private static let cases: [RewriteReplayCase] = [
        RewriteReplayCase(
            id: "developer_requirement_awkward_short",
            mode: .developerRequirement,
            preference: .automatic,
            source: "我感觉我说的短句子它没有做任何的润色，就直接原文输出了。",
            requiredAll: ["我感觉", "短句", "润色"],
            requiredAny: [["直接"], ["原文", "原样"]],
            forbidden: ["用户认为", "建议", "可以尝试"],
            mustRemainQuestion: false,
            mustDifferFromSource: true
        ),
        RewriteReplayCase(
            id: "developer_requirement_clean_short",
            mode: .developerRequirement,
            preference: .automatic,
            source: "你要确保他成功。",
            requiredAll: ["你", "他", "成功"],
            requiredAny: [],
            forbidden: ["用户", "对方", "测试内容", "注意："],
            mustRemainQuestion: false
        ),
        questionCase(
            id: "developer_statement_question",
            mode: .developerStatement,
            preference: .automatic
        ),
        RewriteReplayCase(
            id: "developer_statement_uncertain",
            mode: .developerStatement,
            preference: .automatic,
            source: "我还不确定本地模型是不是突然变慢了。",
            requiredAll: ["本地模型"],
            requiredAny: [
                ["不确定", "尚未确认"],
                ["变慢", "性能下降"],
            ],
            forbidden: [
                "已经确认",
                "可以确定",
                "事实是",
                "出现变慢",
                "出现性能下降",
            ],
            mustRemainQuestion: false
        ),
        questionCase(
            id: "code_commit_question",
            mode: .codeCommit,
            preference: .automatic
        ),
        RewriteReplayCase(
            id: "code_commit_change",
            mode: .codeCommit,
            preference: .automatic,
            source: "把所有整理模式末尾的句号去掉。",
            requiredAll: ["整理模式", "句号"],
            requiredAny: [["去掉", "移除", "删除"]],
            forbidden: [
                "SmartRewriteOutputSanitizer.swift",
                "SwiftUI",
                "AppKit",
                "git commit",
            ],
            mustRemainQuestion: false
        ),
        questionCase(
            id: "polish_question",
            mode: .polish,
            preference: .polish
        ),
        RewriteReplayCase(
            id: "polish_short",
            mode: .polish,
            preference: .polish,
            source: "你要确保他成功。",
            requiredAll: ["你", "他", "成功"],
            requiredAny: [],
            forbidden: ["测试内容", "注意：", "用户", "对方"],
            mustRemainQuestion: false
        ),
        RewriteReplayCase(
            id: "polish_awkward_short",
            mode: .polish,
            preference: .polish,
            source: "我感觉我说的短句子它没有做任何的润色，就直接原文输出了。",
            requiredAll: ["我感觉", "短句", "润色"],
            requiredAny: [["直接"], ["原文", "原样"]],
            forbidden: ["用户认为", "建议", "可以尝试"],
            mustRemainQuestion: false,
            mustDifferFromSource: true
        ),
        RewriteReplayCase(
            id: "note_question",
            mode: .note,
            preference: .instantSummary,
            source: question,
            requiredAll: ["模型", "变慢"],
            requiredAny: [["为什么", "为何", "原因"]],
            forbidden: [
                "内存不足",
                "缓存",
                "网络",
                "负载",
                "建议",
                "可以尝试",
                "可能是",
                "通常",
            ],
            mustRemainQuestion: true,
            maximumListItems: 0
        ),
        RewriteReplayCase(
            id: "note_multiple_points",
            mode: .note,
            preference: .instantSummary,
            source: "今天记录三件事：Qwen3 4B 保持本地整理，下周三下午三点测试，不要在失败后改用 SenseVoice。",
            requiredAll: [
                "Qwen3 4B",
                "下周三下午三点",
                "SenseVoice",
            ],
            requiredAny: [["不要", "不得", "禁止", "不在"]],
            forbidden: ["未明确行动项", "无风险", "待确认："],
            mustRemainQuestion: false,
            minimumListItems: 3
        ),
        questionCase(
            id: "chat_question",
            mode: .chat,
            preference: .chat
        ),
        RewriteReplayCase(
            id: "chat_colloquial",
            mode: .chat,
            preference: .chat,
            source: "我觉得这个速度还是有点慢，你看我们明天要不要再试一次？",
            requiredAll: ["我觉得", "有点慢", "明天", "要不要"],
            requiredAny: [],
            forbidden: ["经评估", "此外", "建议您", "综上"],
            mustRemainQuestion: true
        ),
        questionCase(
            id: "exhaustive_summary_question",
            mode: .exhaustiveSummary,
            preference: .exhaustiveSummary
        ),
        RewriteReplayCase(
            id: "exhaustive_summary_long",
            mode: .exhaustiveSummary,
            preference: .exhaustiveSummary,
            source: "下周三下午三点测试 Qwen3-ASR 1.7B，不是今天下午三点。失败后不要改用 SenseVoice。我想知道这个模型为什么突然变慢了，请告诉我排查方向。",
            requiredAll: [
                "下周三下午三点",
                "今天下午三点",
                "Qwen3-ASR 1.7B",
                "SenseVoice",
                "我",
                "变慢",
            ],
            requiredAny: [
                ["不要", "不得", "禁止"],
                ["为什么", "为何", "原因", "排查方向"],
            ],
            forbidden: [
                "内存不足",
                "缓存未命中",
                "可以尝试",
                "建议检查",
                "可能是由于",
                "需排查",
                "需要排查",
            ],
            mustRemainQuestion: false
        ),
    ]

    private static func questionCase(
        id: String,
        mode: RewriteMode,
        preference: SmartRewritePreference
    ) -> RewriteReplayCase {
        let requiredAll = mode == .developerStatement
            ? ["模型"]
            : ["模型", "变慢"]
        let requiredAny = mode == .developerStatement
            ? [["为什么", "为何"], ["变慢", "性能下降"]]
            : [["为什么", "为何", "原因"]]
        return RewriteReplayCase(
            id: id,
            mode: mode,
            preference: preference,
            source: question,
            requiredAll: requiredAll,
            requiredAny: requiredAny,
            forbidden: [
                "内存不足",
                "缓存",
                "网络",
                "负载",
                "建议",
                "可以尝试",
                "可能是",
                "通常",
                "出现变慢的现象",
                "出现变慢",
                "出现性能下降",
            ],
            mustRemainQuestion: true
        )
    }

    private static func failures(
        for replayCase: RewriteReplayCase,
        output: String
    ) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var failed: [String] = []
        if trimmed.isEmpty {
            failed.append("empty_output")
        }
        if trimmed.hasSuffix("。")
            || (trimmed.hasSuffix(".") && !trimmed.hasSuffix("..")) {
            failed.append("trailing_period")
        }
        if replayCase.mustRemainQuestion
            && !trimmed.contains("？")
            && !trimmed.contains("?") {
            failed.append("question_changed_to_statement")
        }
        if replayCase.mustDifferFromSource
            && canonicalText(trimmed) == canonicalText(replayCase.source) {
            failed.append("awkward_source_copied_verbatim")
        }
        let listItems = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isListItem)
        if replayCase.minimumListItems > 0 {
            if listItems.count < replayCase.minimumListItems {
                failed.append(
                    "list_items:\(listItems.count)<\(replayCase.minimumListItems)"
                )
            }
        }
        if let maximumListItems = replayCase.maximumListItems,
           listItems.count > maximumListItems {
            failed.append(
                "list_items:\(listItems.count)>\(maximumListItems)"
            )
        }
        for fragment in replayCase.requiredAll
            where !trimmed.localizedCaseInsensitiveContains(fragment) {
            failed.append("missing:\(fragment)")
        }
        for alternatives in replayCase.requiredAny
            where !alternatives.contains(where: {
                trimmed.localizedCaseInsensitiveContains($0)
            }) {
            failed.append("missing_any:\(alternatives.joined(separator: "|"))")
        }
        for fragment in replayCase.forbidden
            where trimmed.localizedCaseInsensitiveContains(fragment) {
            failed.append("invented_or_forbidden:\(fragment)")
        }
        for fragment in [
            "我理解你的需求是",
            "整理后如下",
            "最高优先级边界",
            "只做信息转移和表达整理",
            "原始语音文本",
            "请确认",
        ] where trimmed.contains(fragment) {
            failed.append("meta_or_prompt_leak:\(fragment)")
        }
        return failed
    }

    private static func canonicalText(_ text: String) -> String {
        text
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "。.!！?？")
                )
            )
            .replacingOccurrences(
                of: "\\s+",
                with: "",
                options: .regularExpression
            )
    }

    private static func isListItem(_ line: String) -> Bool {
        line.range(
            of: #"^(?:[-*•]\s*|\d+[.、)]\s*|[一二三四五六七八九十]+[、.]\s*)\S"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseArguments() throws -> (
        repository: String,
        outputDirectory: String,
        rounds: Int
    ) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 6 else {
            throw RewriteReplayError.invalidArguments
        }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else {
                throw RewriteReplayError.invalidArguments
            }
            values[arguments[index]] = arguments[index + 1]
            index += 2
        }
        guard let repository = values["--repo-root"],
              let outputDirectory = values["--output-dir"],
              let roundsText = values["--rounds"],
              let rounds = Int(roundsText),
              rounds > 0 else {
            throw RewriteReplayError.invalidArguments
        }
        return (repository, outputDirectory, rounds)
    }

    private static func renderMarkdown(
        _ report: RewriteReplayReport
    ) -> String {
        var lines = [
            "# All Rewrite Modes Semantic Replay",
            "",
            "- Model: \(report.model)",
            "- Rounds: \(report.rounds)",
            "- Generated: \(report.generatedAt)",
            "",
        ]
        for measurement in report.measurements {
            lines.append(
                "## Round \(measurement.round) · \(measurement.mode) · \(measurement.caseID)"
            )
            lines.append("")
            lines.append("**Input**")
            lines.append("")
            lines.append(measurement.source)
            lines.append("")
            lines.append("**Output**")
            lines.append("")
            lines.append(measurement.output)
            lines.append("")
            lines.append(
                String(
                    format: "- TTFT: %.2f ms",
                    measurement.ttftMilliseconds
                )
            )
            lines.append(
                String(
                    format: "- Completion: %.2f ms",
                    measurement.completionMilliseconds
                )
            )
            let failures = measurement.failedChecks.isEmpty
                ? "none"
                : measurement.failedChecks.joined(separator: ", ")
            lines.append("- Failed checks: \(failures)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
