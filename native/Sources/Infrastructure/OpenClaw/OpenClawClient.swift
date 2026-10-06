import Foundation
import Darwin

struct OpenClawResponse: Equatable {
    let replyText: String
    let rawOutput: String
    let displayEvents: [OpenClawDisplayEvent]
}

struct OpenClawDisplayEvent: Equatable {
    enum Kind: String {
        case status
        case progress
        case tool
        case completion
    }

    let kind: Kind
    let text: String
}

enum OpenClawClientError: LocalizedError {
    case emptyMessage
    case cliNotFound(String)
    case launchFailed(String)
    case timedOut
    case commandFailed(Int32, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "OpenClaw 消息为空"
        case .cliNotFound(let path):
            return "找不到 OpenClaw CLI：\(path)"
        case .launchFailed(let message):
            return "无法启动 OpenClaw：\(message)"
        case .timedOut:
            return "OpenClaw 响应超时"
        case .commandFailed(_, let message):
            return message.isEmpty ? "OpenClaw 命令失败" : message
        case .emptyResponse:
            return "OpenClaw 没有返回内容"
        }
    }
}

final class OpenClawCommandClient {
    func send(message: String, settings: OpenClawSettings, timeoutSeconds: TimeInterval = 120) async throws -> OpenClawResponse {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenClawClientError.emptyMessage }

        let cliURL = try resolveCLI(path: settings.cliPath)
        return try await runAgentTurn(
            cliURL: cliURL,
            message: trimmed,
            settings: settings,
            timeoutSeconds: timeoutSeconds
        )
    }

    func health(settings: OpenClawSettings, timeoutSeconds: TimeInterval = 8) async throws -> String {
        let cliURL = try resolveCLI(path: settings.cliPath)
        var args = [
            "gateway", "call", "health",
            "--json",
            "--timeout", "\(Int(timeoutSeconds * 1000))",
        ]
        let gatewayURL = normalized(settings.gatewayURL, fallback: OpenClawSettings.default.gatewayURL)
        if gatewayURL != OpenClawSettings.default.gatewayURL {
            args.append(contentsOf: ["--url", gatewayURL])
        }
        let output = try await runProcess(
            executableURL: cliURL,
            arguments: args,
            timeoutSeconds: timeoutSeconds
        )
        let text = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenClawClientError.emptyResponse }
        return text
    }

    private func runAgentTurn(
        cliURL: URL,
        message: String,
        settings: OpenClawSettings,
        timeoutSeconds: TimeInterval
    ) async throws -> OpenClawResponse {
        var args = [
            "agent",
            "--agent", normalized(settings.agentID, fallback: OpenClawSettings.default.agentID),
            "--message", message,
            "--json",
            "--timeout", "\(Int(timeoutSeconds.rounded()))",
        ]
        let sessionKey = settings.sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionKey.isEmpty {
            args.append(contentsOf: ["--session-key", sessionKey])
        }
        let output = try await runProcess(executableURL: cliURL, arguments: args, timeoutSeconds: timeoutSeconds + 5)
        let raw = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = Self.extractReplyText(from: output.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw OpenClawClientError.emptyResponse }
        return OpenClawResponse(
            replyText: reply,
            rawOutput: raw,
            displayEvents: Self.extractDisplayEvents(from: output.stdout)
        )
    }

    private func resolveCLI(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/usr/bin/openclaw",
        ].filter { !$0.isEmpty }
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw OpenClawClientError.cliNotFound(trimmed.isEmpty ? OpenClawSettings.default.cliPath : trimmed)
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private struct ProcessOutput {
        let stdout: String
        let stderr: String
    }

    private final class ProcessContinuationBox {
        private let lock = NSLock()
        private var didResume = false
        var timeoutWorkItem: DispatchWorkItem?
        let continuation: CheckedContinuation<ProcessOutput, Error>

        init(continuation: CheckedContinuation<ProcessOutput, Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<ProcessOutput, Error>) {
            lock.lock()
            guard !didResume else {
                lock.unlock()
                return
            }
            didResume = true
            lock.unlock()
            timeoutWorkItem?.cancel()
            continuation.resume(with: result)
        }
    }

    private final class CommandOutputBox {
        private let lock = NSLock()
        private var storedData = Data()

        func store(_ data: Data) {
            lock.lock()
            storedData = data
            lock.unlock()
        }

        func load() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let continuationBox = ProcessContinuationBox(continuation: continuation)

            let baseEnvironment = ProcessInfo.processInfo.environment
            let preferredNodeDirectory = Self.compatibleOpenClawNodeDirectory(base: baseEnvironment)
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = Self.openClawCLIEnvironment(
                base: baseEnvironment,
                preferredNodeDirectory: preferredNodeDirectory
            )
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    continuationBox.resume(with: .failure(OpenClawClientError.commandFailed(process.terminationStatus, err.isEmpty ? out : err)))
                    return
                }
                continuationBox.resume(with: .success(ProcessOutput(stdout: out, stderr: err)))
            }

            let workItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                continuationBox.resume(with: .failure(OpenClawClientError.timedOut))
            }
            continuationBox.timeoutWorkItem = workItem
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)

            do {
                try process.run()
            } catch {
                continuationBox.resume(with: .failure(OpenClawClientError.launchFailed(error.localizedDescription)))
            }
        }
    }

    static func processEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/opt/homebrew/opt/node/bin",
            "/opt/homebrew/opt/node@24/bin",
            "/usr/local/bin",
            "/usr/local/sbin"
        ]
        var pathComponents = existingPath.split(separator: ":").map(String.init)
        for path in additionalPaths where !pathComponents.contains(path) {
            pathComponents.append(path)
        }
        environment["PATH"] = pathComponents.joined(separator: ":")
        return environment
    }

    static func openClawCLIEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        preferredNodeDirectory: String? = nil
    ) -> [String: String] {
        var environment = processEnvironment(base: base)
        guard let preferredNodeDirectory,
              !preferredNodeDirectory.isEmpty else {
            return environment
        }
        var pathComponents = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        pathComponents.removeAll { $0 == preferredNodeDirectory }
        pathComponents.insert(preferredNodeDirectory, at: 0)
        environment["PATH"] = pathComponents.joined(separator: ":")
        return environment
    }

    static func isSupportedOpenClawNodeVersion(_ rawVersion: String) -> Bool {
        let normalized = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return false
        }
        switch major {
        case 22:
            return minor > 22 || (minor == 22 && patch >= 3)
        case 24:
            return minor >= 15
        case 25:
            return minor > 9 || (minor == 9 && patch >= 0)
        case 26...:
            return true
        default:
            return false
        }
    }

    static func preferredOpenClawNodeDirectory(
        candidates: [String],
        versionAtPath: (String) -> String?
    ) -> String? {
        var visited = Set<String>()
        for directory in candidates where visited.insert(directory).inserted {
            guard let version = versionAtPath(directory),
                  isSupportedOpenClawNodeVersion(version) else {
                continue
            }
            return directory
        }
        return nil
    }

    private static func compatibleOpenClawNodeDirectory(base: [String: String]) -> String? {
        let inheritedPaths = (base["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = [
            "/opt/homebrew/opt/node@24/bin",
            "/usr/local/opt/node@24/bin",
        ] + inheritedPaths
        return preferredOpenClawNodeDirectory(candidates: candidates) { directory in
            let executableURL = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("node", isDirectory: false)
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }
            return nodeVersion(at: executableURL)
        }
    }

    private static func nodeVersion(at executableURL: URL) -> String? {
        commandOutput(
            executableURL: executableURL,
            arguments: ["--version"],
            timeoutSeconds: 0.5
        )
    }

    static func commandOutput(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> String? {
        let process = Process()
        let stdout = Pipe()
        let outputBox = CommandOutputBox()
        let readerGroup = DispatchGroup()
        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        stdout.fileHandleForWriting.closeFile()
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.store(stdout.fileHandleForReading.readDataToEndOfFile())
            readerGroup.leave()
        }

        if terminationSemaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            if terminationSemaphore.wait(timeout: .now() + 0.2) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 0.5)
            }
            stdout.fileHandleForReading.closeFile()
            _ = readerGroup.wait(timeout: .now() + 0.2)
            return nil
        }
        guard readerGroup.wait(timeout: .now() + 0.2) == .success else { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(
            data: outputBox.load(),
            encoding: .utf8
        )
    }

    static func extractReplyText(from rawOutput: String) -> String {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return displayText(fromRawString: trimmed) ?? ""
        }
        return findText(in: object) ?? ""
    }

    static func extractDisplayEvents(from rawOutput: String) -> [OpenClawDisplayEvent] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var events: [OpenClawDisplayEvent] = []
        collectDisplayEvents(in: object, into: &events)
        var seen = Set<String>()
        return events.filter { event in
            guard !seen.contains(event.text) else { return false }
            seen.insert(event.text)
            return true
        }
    }

    private static func findText(in object: Any) -> String? {
        if let string = object as? String {
            return displayText(fromRawString: string)
        }
        if let dict = object as? [String: Any] {
            for key in ["replyText", "reply", "finalAssistantVisibleText", "finalAssistantRawText", "model_output"] {
                if let value = dict[key], let found = findText(in: value) {
                    return found
                }
            }
            for key in ["result", "payload", "payloads", "data", "output"] {
                if let value = dict[key], let found = findText(in: value) {
                    return found
                }
            }
            for key in ["assistantTexts", "text", "content", "message", "response", "final"] {
                if let value = dict[key], let found = findText(in: value) {
                    return found
                }
            }
            let metadataKeys: Set<String> = [
                "status", "summary", "runId", "meta", "agentMeta", "usage",
                "systemPromptReport", "executionTrace", "requestShaping",
                "completion", "stopReason", "finishReason", "aborted",
                "replayInvalid", "livenessState", "mediaUrl", "kind",
                "type", "toolName", "toolCallId", "id", "createdAt", "updatedAt"
            ]
            for (key, value) in dict where !metadataKeys.contains(key) {
                if let nested = value as? [String: Any], let found = findText(in: nested) {
                    return found
                }
                if let nested = value as? [Any], let found = findText(in: nested) {
                    return found
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let found = findText(in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func displayText(fromRawString string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeJSONPayload(trimmed) {
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return findText(in: object)
        }
        return trimmed
    }

    private static func collectDisplayEvents(in object: Any, into events: inout [OpenClawDisplayEvent]) {
        if let dict = object as? [String: Any] {
            if let state = readableState(from: dict["livenessState"] ?? dict["state"] ?? dict["phase"] ?? dict["status"]) {
                events.append(OpenClawDisplayEvent(kind: state.kind, text: state.text))
            }
            if let progress = readableProgress(from: dict["progress"]) {
                events.append(OpenClawDisplayEvent(kind: .progress, text: progress))
            }
            if let progress = readableProgress(from: dict["progressMessage"] ?? dict["progressText"]) {
                events.append(OpenClawDisplayEvent(kind: .progress, text: progress))
            }
            if let tool = readableToolSummary(from: dict) {
                events.append(OpenClawDisplayEvent(kind: .tool, text: tool))
            }

            let skippedKeys: Set<String> = [
                "replyText", "reply", "finalAssistantVisibleText", "finalAssistantRawText",
                "assistantTexts", "text", "content", "message", "response", "final",
                "model_output", "usage", "meta", "agentMeta", "systemPromptReport",
                "requestShaping"
            ]
            for (key, value) in dict where !skippedKeys.contains(key) {
                collectDisplayEvents(in: value, into: &events)
            }
            return
        }
        if let array = object as? [Any] {
            for value in array {
                collectDisplayEvents(in: value, into: &events)
            }
        }
    }

    private static func readableState(from value: Any?) -> OpenClawDisplayEvent? {
        guard let raw = safeDisplayString(value)?.lowercased() else { return nil }
        switch raw {
        case "executing", "execute", "tool_running", "running_tool":
            return OpenClawDisplayEvent(kind: .status, text: "OpenClaw 正在执行")
        case "thinking", "reasoning", "planning":
            return OpenClawDisplayEvent(kind: .status, text: "OpenClaw 正在思考")
        case "running", "processing", "in_progress":
            return OpenClawDisplayEvent(kind: .status, text: "OpenClaw 正在处理")
        case "queued", "pending", "received":
            return OpenClawDisplayEvent(kind: .status, text: "OpenClaw 已接收，等待处理")
        case "completed", "complete", "succeeded", "success", "ok":
            return OpenClawDisplayEvent(kind: .completion, text: "OpenClaw 已完成")
        case "failed", "error", "aborted", "timeout":
            return OpenClawDisplayEvent(kind: .status, text: "OpenClaw 执行异常")
        default:
            return nil
        }
    }

    private static func readableProgress(from value: Any?) -> String? {
        if let string = safeDisplayString(value) {
            return string
        }
        guard let dict = value as? [String: Any] else { return nil }
        for key in ["message", "text", "label", "summary"] {
            if let text = safeDisplayString(dict[key]) {
                return text
            }
        }
        return nil
    }

    private static func readableToolSummary(from dict: [String: Any]) -> String? {
        guard let toolName = safeDisplayString(dict["toolName"] ?? dict["tool"] ?? dict["name"]) else {
            return nil
        }
        guard dict["toolName"] != nil || (safeDisplayString(dict["kind"]) == "tool") || (safeDisplayString(dict["type"]) == "tool") else {
            return nil
        }
        if let summary = safeDisplayString(dict["summary"] ?? dict["description"] ?? dict["message"]) {
            return "工具：\(toolName) · \(summary)"
        }
        return "工具：\(toolName)"
    }

    private static func safeDisplayString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 160, !looksLikeJSONPayload(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func looksLikeJSONPayload(_ string: String) -> Bool {
        (string.hasPrefix("{") && string.hasSuffix("}"))
            || (string.hasPrefix("[") && string.hasSuffix("]"))
    }
}
