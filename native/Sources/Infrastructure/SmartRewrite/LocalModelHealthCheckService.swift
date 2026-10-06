import Foundation

enum LocalModelHealthCheckStage: String, CaseIterable, Equatable {
    case runtimeImport
    case modelIntegrity
    case modelWarmup
    case minimalGeneration
}

struct LocalModelHealthDiagnosticContext: Equatable {
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let modelID: String
}

struct LocalModelHealthCheckReport: Equatable {
    let passed: Bool
    let failedStage: LocalModelHealthCheckStage?
    let errorCode: String?
    let userMessage: String
    let technicalDetail: String?
    let elapsedMS: Double
    let metrics: ManagedLLMMetrics?
    let diagnosticText: String
}

final class LocalModelHealthCheckService: @unchecked Sendable {
    struct Dependencies {
        let runtimeProbe: () -> ManagedMLXRuntimeProbeResult
        let modelReadiness: () -> ManagedLLMReadiness
        let runtime: ManagedLLMRuntime
        let isRuntimeBusy: () -> Bool
        let modelDirectory: () -> URL
        let diagnosticContext: () -> LocalModelHealthDiagnosticContext
        let now: () -> TimeInterval
        let log: (String) -> Void

        init(
            runtimeProbe: @escaping () -> ManagedMLXRuntimeProbeResult,
            modelReadiness: @escaping () -> ManagedLLMReadiness,
            runtime: ManagedLLMRuntime,
            isRuntimeBusy: @escaping () -> Bool,
            modelDirectory: @escaping () -> URL,
            diagnosticContext: @escaping () -> LocalModelHealthDiagnosticContext,
            now: @escaping () -> TimeInterval,
            log: @escaping (String) -> Void = { _ in }
        ) {
            self.runtimeProbe = runtimeProbe
            self.modelReadiness = modelReadiness
            self.runtime = runtime
            self.isRuntimeBusy = isRuntimeBusy
            self.modelDirectory = modelDirectory
            self.diagnosticContext = diagnosticContext
            self.now = now
            self.log = log
        }
    }

    private static let systemPrompt =
        "你是 TypeWhale 本地模型健康检测。只输出指定短语，不要解释。"
    private static let userPrompt = "请只输出：模型正常"

    private let dependencies: Dependencies
    private let stateLock = NSLock()
    private var isRunning = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func run(
        onProgress: @escaping (LocalModelHealthCheckStage) -> Void
    ) async -> LocalModelHealthCheckReport {
        let startedAt = dependencies.now()
        guard beginRun() else {
            return failure(
                stage: nil,
                code: "check_in_progress",
                userMessage: "本地模型检测正在进行，请等待本次检测完成",
                technicalDetail: nil,
                startedAt: startedAt
            )
        }
        defer { endRun() }

        guard !dependencies.isRuntimeBusy() else {
            return failure(
                stage: nil,
                code: "runtime_busy",
                userMessage: "本地模型正在处理其他任务，请稍后再检测",
                technicalDetail: nil,
                startedAt: startedAt
            )
        }

        dependencies.log("local_model_health_check start")

        onProgress(.runtimeImport)
        dependencies.log("local_model_health_check stage=runtime_import")
        let runtimeProbe = await Task.detached(priority: .utility) { [self] in
            dependencies.runtimeProbe()
        }.value
        guard !Task.isCancelled else {
            return cancellationFailure(stage: .runtimeImport, startedAt: startedAt)
        }
        guard runtimeProbe.isReady else {
            return failure(
                stage: .runtimeImport,
                code: runtimeProbe.errorCode ?? "runtime_import_failed",
                userMessage: runtimeProbe.userMessage ?? "本地模型运行环境不可用",
                technicalDetail: runtimeProbe.technicalDetail,
                startedAt: startedAt
            )
        }

        onProgress(.modelIntegrity)
        dependencies.log("local_model_health_check stage=model_integrity")
        let modelReadiness = await Task.detached(priority: .utility) { [self] in
            dependencies.modelReadiness()
        }.value
        guard !Task.isCancelled else {
            return cancellationFailure(stage: .modelIntegrity, startedAt: startedAt)
        }
        switch modelReadiness {
        case .missing:
            return failure(
                stage: .modelIntegrity,
                code: "model_missing",
                userMessage: "Qwen3 4B 本地模型尚未安装",
                technicalDetail: nil,
                startedAt: startedAt
            )
        case .invalid(let reason):
            return failure(
                stage: .modelIntegrity,
                code: "model_integrity_failed",
                userMessage: "Qwen3 4B 模型文件不完整或已损坏",
                technicalDetail: reason,
                startedAt: startedAt
            )
        case .ready:
            break
        }

        guard !dependencies.isRuntimeBusy() else {
            return runtimeBusyFailure(stage: .modelWarmup, startedAt: startedAt)
        }
        onProgress(.modelWarmup)
        dependencies.log("local_model_health_check stage=model_warmup")
        let warmupRequest = request(command: .warmup, maxTokens: 1)
        let warmupMetrics: ManagedLLMMetrics?
        do {
            let response = try await performOnlyIfRuntimeIdle(warmupRequest)
            _ = try ManagedLLMResponseValidator.validate(
                response,
                requireFinalText: false
            )
            warmupMetrics = response.metrics
        } catch {
            return responseFailure(
                error,
                stage: .modelWarmup,
                rejectedCode: "warmup_rejected",
                startedAt: startedAt
            )
        }

        guard !dependencies.isRuntimeBusy() else {
            return runtimeBusyFailure(stage: .minimalGeneration, startedAt: startedAt)
        }
        onProgress(.minimalGeneration)
        dependencies.log("local_model_health_check stage=minimal_generation")
        let generationRequest = request(command: .rewrite, maxTokens: 16)
        let generationResponse: ManagedMLXLLMResponse
        do {
            generationResponse = try await performOnlyIfRuntimeIdle(generationRequest)
            _ = try ManagedLLMResponseValidator.validate(
                generationResponse,
                requireFinalText: true
            )
        } catch ManagedLLMResponseValidationError.emptyFinalText {
            return failure(
                stage: .minimalGeneration,
                code: "generation_empty",
                userMessage: "本地模型已加载，但没有生成有效结果",
                technicalDetail: nil,
                startedAt: startedAt
            )
        } catch {
            return responseFailure(
                error,
                stage: .minimalGeneration,
                rejectedCode: "generation_rejected",
                startedAt: startedAt
            )
        }

        let elapsedMS = elapsed(since: startedAt)
        let combinedMetrics = combineMetrics(
            warmup: warmupMetrics,
            generation: generationResponse.metrics
        )
        let context = dependencies.diagnosticContext()
        let report = LocalModelHealthCheckReport(
            passed: true,
            failedStage: nil,
            errorCode: nil,
            userMessage: "本地模型正常 · 可用于智能整理",
            technicalDetail: nil,
            elapsedMS: elapsedMS,
            metrics: combinedMetrics,
            diagnosticText: diagnosticText(
                context: context,
                passed: true,
                stage: .minimalGeneration,
                errorCode: nil,
                elapsedMS: elapsedMS,
                metrics: combinedMetrics,
                technicalDetail: nil
            )
        )
        dependencies.log(
            "local_model_health_check done elapsed_ms=\(Int(elapsedMS.rounded()))"
        )
        return report
    }

    private func combineMetrics(
        warmup: ManagedLLMMetrics?,
        generation: ManagedLLMMetrics?
    ) -> ManagedLLMMetrics? {
        guard warmup != nil || generation != nil else { return nil }
        let peakRSSBytes = [warmup?.peakRSSBytes, generation?.peakRSSBytes]
            .compactMap { $0 }
            .max()
        return ManagedLLMMetrics(
            loadMS: warmup?.loadMS ?? generation?.loadMS,
            ttftMS: generation?.ttftMS,
            completionMS: generation?.completionMS,
            tokensPerSecond: generation?.tokensPerSecond,
            peakRSSBytes: peakRSSBytes,
            promptTokens: generation?.promptTokens,
            completionTokens: generation?.completionTokens,
            promptCacheHit: generation?.promptCacheHit,
            promptCacheReusedTokens: generation?.promptCacheReusedTokens,
            promptTokensEvaluated: generation?.promptTokensEvaluated
        )
    }

    private func request(
        command: ManagedMLXLLMCommand,
        maxTokens: Int
    ) -> ManagedMLXLLMRequest {
        ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: UUID().uuidString,
            command: command,
            modelDirectory: dependencies.modelDirectory().path,
            systemPrompt: command == .warmup ? "" : Self.systemPrompt,
            userPrompt: command == .warmup ? "" : Self.userPrompt,
            reasoning: .low,
            maxTokens: maxTokens
        )
    }

    private func performOnlyIfRuntimeIdle(
        _ request: ManagedMLXLLMRequest
    ) async throws -> ManagedMLXLLMResponse {
        if let idleRuntime = dependencies.runtime as? ManagedLLMRuntimeIdlePerforming {
            return try await idleRuntime.performIfIdle(request)
        }
        guard !dependencies.isRuntimeBusy() else {
            throw ManagedLLMRuntimeError.busy
        }
        return try await dependencies.runtime.perform(request)
    }

    private func responseFailure(
        _ error: Error,
        stage: LocalModelHealthCheckStage,
        rejectedCode: String,
        startedAt: TimeInterval
    ) -> LocalModelHealthCheckReport {
        let code: String
        let message: String
        switch error {
        case ManagedLLMResponseValidationError.rejected:
            code = rejectedCode
            message = stage == .modelWarmup
                ? "本地模型预热失败"
                : "本地模型最小生成失败"
        case ManagedLLMResponseValidationError.cancelled,
             ManagedLLMRuntimeError.cancelled:
            code = "runtime_cancelled"
            message = "本地模型检测已取消"
        case ManagedLLMResponseValidationError.invalidProtocol,
             ManagedLLMRuntimeError.invalidResponse,
             ManagedLLMRuntimeError.responseIDMismatch,
             ManagedLLMRuntimeError.responseTooLarge:
            code = "runtime_invalid_response"
            message = "本地模型返回了无法识别的响应"
        case ManagedLLMResponseValidationError.emptyFinalText:
            code = "generation_empty"
            message = "本地模型已加载，但没有生成有效结果"
        case ManagedLLMRuntimeError.timedOut:
            code = "runtime_timeout"
            message = "本地模型响应超时，请稍后重试"
        case ManagedLLMRuntimeError.unavailable:
            code = "runtime_unavailable"
            message = "本地模型运行环境不可用"
        case ManagedLLMRuntimeError.busy:
            code = "runtime_busy"
            message = "本地模型正在处理其他任务，请稍后再检测"
        case ManagedLLMRuntimeError.helperExited:
            code = "runtime_worker_exited"
            message = "本地模型进程意外退出"
        default:
            code = "runtime_request_failed"
            message = "本地模型检测请求失败"
        }
        return failure(
            stage: stage,
            code: code,
            userMessage: message,
            technicalDetail: error.localizedDescription,
            startedAt: startedAt
        )
    }

    private func runtimeBusyFailure(
        stage: LocalModelHealthCheckStage?,
        startedAt: TimeInterval
    ) -> LocalModelHealthCheckReport {
        failure(
            stage: stage,
            code: "runtime_busy",
            userMessage: "本地模型正在处理其他任务，请稍后再检测",
            technicalDetail: nil,
            startedAt: startedAt
        )
    }

    private func cancellationFailure(
        stage: LocalModelHealthCheckStage?,
        startedAt: TimeInterval
    ) -> LocalModelHealthCheckReport {
        failure(
            stage: stage,
            code: "runtime_cancelled",
            userMessage: "本地模型检测已取消",
            technicalDetail: nil,
            startedAt: startedAt
        )
    }

    private func failure(
        stage: LocalModelHealthCheckStage?,
        code: String,
        userMessage: String,
        technicalDetail: String?,
        startedAt: TimeInterval
    ) -> LocalModelHealthCheckReport {
        let elapsedMS = elapsed(since: startedAt)
        let safeDetail = Self.sanitize(technicalDetail)
        let context = dependencies.diagnosticContext()
        let report = LocalModelHealthCheckReport(
            passed: false,
            failedStage: stage,
            errorCode: code,
            userMessage: userMessage,
            technicalDetail: safeDetail,
            elapsedMS: elapsedMS,
            metrics: nil,
            diagnosticText: diagnosticText(
                context: context,
                passed: false,
                stage: stage,
                errorCode: code,
                elapsedMS: elapsedMS,
                metrics: nil,
                technicalDetail: safeDetail
            )
        )
        dependencies.log(
            "local_model_health_check failed stage=\(stage?.rawValue ?? "none") code=\(code) elapsed_ms=\(Int(elapsedMS.rounded()))"
        )
        return report
    }

    private func diagnosticText(
        context: LocalModelHealthDiagnosticContext,
        passed: Bool,
        stage: LocalModelHealthCheckStage?,
        errorCode: String?,
        elapsedMS: Double,
        metrics: ManagedLLMMetrics?,
        technicalDetail: String?
    ) -> String {
        var lines = [
            "TypeWhale \(context.appVersion) (Build \(context.appBuild))",
            "System: \(context.operatingSystem)",
            "Model: \(context.modelID)",
            "Result: \(passed ? "passed" : "failed")",
            "Stage: \(stage?.rawValue ?? "none")",
            "Error code: \(errorCode ?? "none")",
            "Elapsed: \(Int(elapsedMS.rounded())) ms",
        ]
        if let metrics {
            lines.append("Load: \(format(metrics.loadMS)) ms")
            lines.append("TTFT: \(format(metrics.ttftMS)) ms")
            lines.append("Completion: \(format(metrics.completionMS)) ms")
            lines.append("Tokens/s: \(format(metrics.tokensPerSecond))")
            if let peakRSSBytes = metrics.peakRSSBytes {
                lines.append("Peak RSS: \(peakRSSBytes / 1_048_576) MB")
            }
        }
        if let technicalDetail, !technicalDetail.isEmpty {
            lines.append("Detail: \(technicalDetail)")
        }
        return Self.sanitize(lines.joined(separator: "\n")) ?? ""
    }

    private func elapsed(since startedAt: TimeInterval) -> Double {
        max(0, (dependencies.now() - startedAt) * 1_000)
    }

    private func beginRun() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    private func endRun() {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }

    private static func sanitize(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let patterns = [
            #"(?i)sk-[A-Za-z0-9._-]+"#,
            #"(?i)(api[_ -]?key\s*[:=]\s*)\S+"#,
            #"(?i)(authorization\s*[:=]\s*)\S+"#,
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = expression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: "$1[REDACTED]"
            )
        }
        let allowed = value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar.value >= 0x20
        }
        let sanitized = String(String.UnicodeScalarView(allowed))
        let bounded = String(sanitized.prefix(8_192))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? nil : bounded
    }
}
