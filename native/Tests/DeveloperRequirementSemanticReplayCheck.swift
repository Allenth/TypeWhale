import Foundation
import Darwin

private func semanticNumeric(_ value: Any?) -> Double {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let number = value as? Double {
        return number
    }
    return 0
}

private struct SemanticReplayCase {
    let id: String
    let source: String
}

private struct SemanticReplayMeasurement: Codable {
    let round: Int
    let caseID: String
    let source: String
    let output: String
    let ttftMilliseconds: Double
    let completionMilliseconds: Double
    let failedChecks: [String]
}

private struct SemanticReplayReport: Codable {
    let model: String
    let rounds: Int
    let generatedAt: String
    let measurements: [SemanticReplayMeasurement]
}

private enum SemanticReplayError: Error, LocalizedError {
    case invalidArguments
    case missingPath(String)
    case invalidResponse(String)
    case workerEnded
    case workerFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: DeveloperRequirementSemanticReplayCheck --repo-root <path> --output-dir <path> --rounds <count>"
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

private final class SemanticJSONLineWorker {
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
            throw SemanticReplayError.invalidResponse("worker returned non-object JSON")
        }
        guard value["ok"] as? Bool == true else {
            let message = value["error_message"] as? String
                ?? value["error"] as? String
                ?? "unknown"
            throw SemanticReplayError.workerFailure(message)
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
                throw SemanticReplayError.workerEnded
            }
            readBuffer.append(chunk)
        }
    }
}

private final class SemanticReplayEngine: SmartRewriteEngine {
    let displayName = "Qwen3 4B Instruct"
    let logName = "semantic_replay_mlx"
    let usesLocalCostGuard = false

    private let worker: SemanticJSONLineWorker
    private let modelDirectory: URL
    private(set) var ttftMilliseconds = 0.0
    private(set) var completionMilliseconds = 0.0

    init(worker: SemanticJSONLineWorker, modelDirectory: URL) {
        self.worker = worker
        self.modelDirectory = modelDirectory
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
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
            throw SemanticReplayError.invalidResponse("final_text is missing")
        }
        let metrics = response["metrics"] as? [String: Any] ?? [:]
        ttftMilliseconds = semanticNumeric(metrics["ttft_ms"])
        completionMilliseconds = semanticNumeric(metrics["completion_ms"])
        return SmartRewriteEngineOutput(
            text: SmartRewriteOutputSanitizer.cleanLocalModel(rawOutput),
            usage: nil
        )
    }
}

@main
private enum DeveloperRequirementSemanticReplayCheck {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs(
                "developer_semantic_replay_failed: \(error.localizedDescription)\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
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
                throw SemanticReplayError.missingPath(url.path)
            }
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let worker = try SemanticJSONLineWorker(
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

        let engine = SemanticReplayEngine(
            worker: worker,
            modelDirectory: modelDirectory
        )
        let router = SmartInputRouter(engine: engine)
        let context = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        var measurements: [SemanticReplayMeasurement] = []
        for round in 1...arguments.rounds {
            for replayCase in cases {
                let result = await router.rewrite(
                    rawText: replayCase.source,
                    preference: .developerRequirement,
                    context: context
                )
                measurements.append(
                    SemanticReplayMeasurement(
                        round: round,
                        caseID: replayCase.id,
                        source: replayCase.source,
                        output: result.text,
                        ttftMilliseconds: engine.ttftMilliseconds,
                        completionMilliseconds: engine.completionMilliseconds,
                        failedChecks: failures(
                            for: replayCase,
                            output: result.text
                        )
                    )
                )
            }
        }

        let report = SemanticReplayReport(
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
                "round=\($0.round) case=\($0.caseID) failures=\($0.failedChecks.joined(separator: ","))"
            }
            throw SemanticReplayError.invalidResponse(
                details.joined(separator: "; ")
            )
        }
    }

    private static let cases = [
        SemanticReplayCase(
            id: "countdown",
            source: "两秒自动取消那个条不显不显示取消按钮，点击整条后取消它的位置正好跟胶囊是中心对齐的。"
        ),
        SemanticReplayCase(
            id: "short_requirement",
            source: "你要确保他成功。"
        ),
        SemanticReplayCase(
            id: "ui_feedback",
            source: "这个颜色不太好看。分贝那里的颜色恢复成以前的颜色，另外绿色镜框也恢复成跟以前分贝单位一样的颜色。"
        ),
        SemanticReplayCase(
            id: "ordered_steps",
            source: "第一，保存原始识别结果；第二，记录整理结果；第三，比较删减和意思变化；最后再决定是否修改提示词。"
        ),
        SemanticReplayCase(
            id: "retain_existing_behavior",
            source: "取消按钮去掉，但提前按回车取消倒计时、防止再次发送的逻辑要继续保留。"
        ),
        SemanticReplayCase(
            id: "unknown_term",
            source: "先检查 Combinite 三 ASR 的表现，不确定这个名称时保留原话，不要猜成其他模型。"
        ),
        SemanticReplayCase(
            id: "regression_signal",
            source: "以前点击胶囊就能立即开始录音，现在要等动画结束才响应，这不是普通优化建议，是已经发生的体验退化。我要求恢复以前点击后立即响应的体验。"
        ),
        SemanticReplayCase(
            id: "investigation_only",
            source: "先不要修改代码。先检查最近三次录音日志，确认问题发生在识别、整理还是粘贴阶段，再决定是否修改提示词。"
        ),
        SemanticReplayCase(
            id: "goal_and_suggestion",
            source: "目标是让第一次语音输入也能立即响应。我倾向于让模型保持热加载，但这只是实现建议，不要把它写成唯一方案。"
        ),
        SemanticReplayCase(
            id: "prompt_calibration",
            source: "我们现在只校准开发需求提示词，不急着修改代码。每次修改都要重新审阅和明确定义整份提示词，不能只做小修小改，也不能让模型丢失前文或因为规则重复而混乱。"
        ),
    ]

    private static func failures(
        for replayCase: SemanticReplayCase,
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
        for phrase in [
            "我理解你的需求是",
            "如果理解正确",
            "如果以上理解",
            "请确认",
        ] where trimmed.contains(phrase) {
            failed.append("confirmation_language")
        }

        switch replayCase.id {
        case "countdown":
            if !containsAny(
                trimmed,
                [
                    "不显示单独",
                    "不显示独立",
                    "不显示取消按钮",
                    "不再显示",
                    "去掉取消按钮",
                    "移除取消按钮",
                ]
            ) {
                failed.append("cancel_button_removal")
            }
            if !containsAny(
                trimmed,
                ["点击整条", "整条倒计时", "任意位置"]
            ) {
                failed.append("whole_strip_click")
            }
            if !containsAny(
                trimmed,
                ["中心对齐", "中心重合", "中心点重合"]
            ) {
                failed.append("capsule_center_alignment")
            }
            if trimmed.contains("水平中心对齐")
                && !containsAny(trimmed, ["纵向", "垂直", "中心点重合"]) {
                failed.append("center_weakened_to_horizontal")
            }
        case "short_requirement":
            if !trimmed.contains("你")
                || !trimmed.contains("确保")
                || !trimmed.contains("成功") {
                failed.append("short_meaning_changed")
            }
            if trimmed.count > 24 || trimmed.contains("\n") {
                failed.append("short_requirement_expanded")
            }
        case "ui_feedback":
            for anchor in ["分贝", "绿色镜框", "恢复"]
            where !trimmed.contains(anchor) {
                failed.append("missing_\(anchor)")
            }
            let clauses = trimmed
                .replacingOccurrences(of: "；", with: "。")
                .components(separatedBy: CharacterSet(charactersIn: "。\n"))
            let hasDecibelClause = clauses.contains {
                $0.contains("分贝")
                    && $0.contains("恢复")
                    && !$0.contains("绿色镜框")
            }
            let hasFrameClause = clauses.contains {
                $0.contains("绿色镜框") && $0.contains("恢复")
            }
            if !hasDecibelClause || !hasFrameClause {
                failed.append("ui_requirements_not_separated")
            }
        case "ordered_steps":
            let anchors = ["第一", "第二", "第三"]
            var lastIndex = trimmed.startIndex
            for anchor in anchors {
                guard let range = trimmed.range(
                    of: anchor,
                    range: lastIndex..<trimmed.endIndex
                ) else {
                    failed.append("ordered_steps_\(anchor)")
                    continue
                }
                lastIndex = range.upperBound
            }
            if let finalRange = trimmed.range(
                of: "最后",
                range: lastIndex..<trimmed.endIndex
            ) ?? trimmed.range(
                of: "第四",
                range: lastIndex..<trimmed.endIndex
            ) {
                lastIndex = finalRange.upperBound
            } else {
                failed.append("ordered_steps_final")
            }
        case "retain_existing_behavior":
            for anchor in ["取消按钮", "回车", "保留"]
            where !trimmed.contains(anchor) {
                failed.append("missing_\(anchor)")
            }
            if !containsAny(trimmed, ["再次发送", "重复发送", "二次发送"]) {
                failed.append("missing_duplicate_send_prevention")
            }
        case "unknown_term":
            for anchor in ["Combinite", "ASR"]
            where !trimmed.contains(anchor) {
                failed.append("unknown_term_changed")
            }
            if !containsAny(
                trimmed,
                ["保留原话", "保留原名称", "保留原称"]
            ) {
                failed.append("unknown_term_preservation")
            }
            if !containsAny(
                trimmed,
                [
                    "不要猜",
                    "不得猜",
                    "不猜",
                    "不得推测",
                    "不要推测",
                    "不替换为其他模型",
                    "不得替换为其他模型",
                    "不进行猜测",
                    "不作替换或猜测",
                ]
            ) {
                failed.append("unknown_term_no_guess")
            }
        case "regression_signal":
            for anchor in ["以前", "现在", "退化", "立即"]
            where !trimmed.contains(anchor) {
                failed.append("missing_regression_\(anchor)")
            }
            if containsAny(trimmed, ["可以考虑", "建议优化", "后续优化"]) {
                failed.append("regression_weakened")
            }
        case "investigation_only":
            for anchor in ["不要修改代码", "最近三次", "识别", "整理", "粘贴", "再决定"]
            where !trimmed.contains(anchor) {
                failed.append("missing_investigation_\(anchor)")
            }
            if containsAny(trimmed, ["修改代码以", "开始修改", "直接修改提示词"]) {
                failed.append("investigation_advanced_to_execution")
            }
        case "goal_and_suggestion":
            for anchor in ["第一次", "立即响应", "热加载", "实现建议"]
            where !trimmed.contains(anchor) {
                failed.append("missing_goal_suggestion_\(anchor)")
            }
            if !containsAny(trimmed, ["唯一方案", "唯一解决方案"]) {
                failed.append("missing_goal_suggestion_unique_solution")
            }
            if containsAny(trimmed, ["必须保持热加载", "只能保持热加载"]) {
                failed.append("suggestion_became_mandatory")
            }
        case "prompt_calibration":
            for anchor in ["只校准", "不急着修改代码", "重新审阅", "明确定义", "小修小改", "前文", "混乱"]
            where !trimmed.contains(anchor) {
                failed.append("missing_calibration_\(anchor)")
            }
            if containsAny(trimmed, ["已经修改", "完成修改", "开始实施"]) {
                failed.append("calibration_advanced_to_execution")
            }
        default:
            failed.append("unknown_case")
        }
        return failed
    }

    private static func containsAny(
        _ text: String,
        _ candidates: [String]
    ) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private static func parseArguments() throws -> (
        repository: String,
        outputDirectory: String,
        rounds: Int
    ) {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        guard let repository = value(after: "--repo-root"),
              let outputDirectory = value(after: "--output-dir"),
              let roundsRaw = value(after: "--rounds"),
              let rounds = Int(roundsRaw),
              rounds > 0 else {
            throw SemanticReplayError.invalidArguments
        }
        return (repository, outputDirectory, rounds)
    }

    private static func renderMarkdown(
        _ report: SemanticReplayReport
    ) -> String {
        var lines = [
            "# Developer Requirement Semantic Replay",
            "",
            "- Model: \(report.model)",
            "- Rounds: \(report.rounds)",
            "- Generated: \(report.generatedAt)",
            "",
        ]
        for measurement in report.measurements {
            lines.append(
                "## Round \(measurement.round) · \(measurement.caseID)"
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
            lines.append(
                "- Failed checks: "
                    + (
                        measurement.failedChecks.isEmpty
                        ? "none"
                        : measurement.failedChecks.joined(separator: ", ")
                    )
            )
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
