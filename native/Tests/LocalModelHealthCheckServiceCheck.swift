import Foundation

private final class HealthCheckFakeRuntime: ManagedLLMRuntime {
    var responses: [ManagedMLXLLMResponse] = []
    var error: Error?
    private(set) var requests: [ManagedMLXLLMRequest] = []

    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        requests.append(request)
        if let error { throw error }
        precondition(!responses.isEmpty, "missing fake response")
        var response = responses.removeFirst()
        response = ManagedMLXLLMResponse(
            protocolVersion: response.protocolVersion,
            id: request.id,
            ok: response.ok,
            finalText: response.finalText,
            errorCode: response.errorCode,
            errorMessage: response.errorMessage,
            metrics: response.metrics,
            cancelled: response.cancelled
        )
        return response
    }

    func cancelCurrentRequest() {}
    func stop() {}
}

private final class AtomicIdleFakeRuntime: ManagedLLMRuntime, ManagedLLMRuntimeIdlePerforming {
    private(set) var regularPerformCount = 0
    private(set) var idlePerformCount = 0

    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        _ = request
        regularPerformCount += 1
        throw ManagedLLMRuntimeError.unavailable
    }

    func performIfIdle(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        _ = request
        idlePerformCount += 1
        throw ManagedLLMRuntimeError.busy
    }

    func cancelCurrentRequest() {}
    func stop() {}
}

@main
struct LocalModelHealthCheckServiceCheck {
    static func main() async throws {
        try await verifySuccessfulStageOrderAndPrivacy()
        try await verifyRuntimeFailureStopsAllLaterStages()
        try await verifyBusyRuntimeIsNotQueued()
        try await verifyRuntimeBecomingBusyStopsLaterStages()
        try await verifyWarmupRejectionStopsGeneration()
        try await verifyGenerationRejection()
        try await verifyEmptyGeneration()
        try await verifyModelFailures()
        try await verifyRuntimeTransportFailure()
        try await verifyAtomicIdleRuntimeBusyMapping()
        try await verifyCancellationDoesNotReachWorker()
        print("LocalModelHealthCheckServiceCheck passed")
    }

    private static func verifySuccessfulStageOrderAndPrivacy() async throws {
        let runtime = HealthCheckFakeRuntime()
        runtime.responses = [
            response(ok: true, finalText: nil, metrics: metrics(loadMS: 120)),
            response(ok: true, finalText: "sk-secret-output", metrics: metrics(loadMS: 0)),
        ]
        var stages: [LocalModelHealthCheckStage] = []
        var nowValues = [100.0, 100.25]
        let service = makeService(
            runtime: runtime,
            now: { nowValues.removeFirst() }
        )

        let report = await service.run { stages.append($0) }

        precondition(report.passed)
        precondition(report.failedStage == nil)
        precondition(report.errorCode == nil)
        precondition(report.elapsedMS == 250)
        precondition(report.metrics?.loadMS == 120)
        precondition(stages == [
            .runtimeImport,
            .modelIntegrity,
            .modelWarmup,
            .minimalGeneration,
        ])
        precondition(runtime.requests.map(\.command) == [.warmup, .rewrite])
        precondition(runtime.requests.allSatisfy {
            $0.modelDirectory == "/managed/qwen3-4b-instruct-2507-4bit"
        })
        precondition(runtime.requests[1].maxTokens <= 32)
        precondition(!report.diagnosticText.contains(runtime.requests[1].systemPrompt))
        precondition(!report.diagnosticText.contains(runtime.requests[1].userPrompt))
        precondition(!report.diagnosticText.contains("sk-secret-output"))
        precondition(!report.diagnosticText.contains("sk-test-user-key"))
        precondition(report.diagnosticText.contains("TypeWhale 9.9.9 (Build 999)"))
        precondition(report.diagnosticText.contains("minimalGeneration"))
    }

    private static func verifyRuntimeFailureStopsAllLaterStages() async throws {
        let runtime = HealthCheckFakeRuntime()
        var readinessCalls = 0
        let service = makeService(
            runtime: runtime,
            runtimeProbe: {
                .failure(
                    code: "runtime_import_failed",
                    userMessage: "运行环境与当前 macOS 不兼容",
                    technicalDetail: "dlopen malformed __thread_bss token=sk-test-user-key"
                )
            },
            modelReadiness: {
                readinessCalls += 1
                return .ready(URL(fileURLWithPath: "/unused"))
            }
        )
        var stages: [LocalModelHealthCheckStage] = []

        let report = await service.run { stages.append($0) }

        precondition(!report.passed)
        precondition(report.failedStage == .runtimeImport)
        precondition(report.errorCode == "runtime_import_failed")
        precondition(report.userMessage == "运行环境与当前 macOS 不兼容")
        precondition(report.technicalDetail?.contains("__thread_bss") == true)
        precondition(report.technicalDetail?.contains("sk-test-user-key") == false)
        precondition(stages == [.runtimeImport])
        precondition(readinessCalls == 0)
        precondition(runtime.requests.isEmpty)
    }

    private static func verifyBusyRuntimeIsNotQueued() async throws {
        let runtime = HealthCheckFakeRuntime()
        var stages: [LocalModelHealthCheckStage] = []
        let service = makeService(runtime: runtime, isRuntimeBusy: { true })

        let report = await service.run { stages.append($0) }

        precondition(!report.passed)
        precondition(report.failedStage == nil)
        precondition(report.errorCode == "runtime_busy")
        precondition(stages.isEmpty)
        precondition(runtime.requests.isEmpty)
    }

    private static func verifyRuntimeBecomingBusyStopsLaterStages() async throws {
        let beforeWarmupRuntime = HealthCheckFakeRuntime()
        var busyBeforeWarmup = false
        let beforeWarmup = await makeService(
            runtime: beforeWarmupRuntime,
            modelReadiness: {
                busyBeforeWarmup = true
                return .ready(URL(fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit"))
            },
            isRuntimeBusy: { busyBeforeWarmup }
        ).run { _ in }
        precondition(beforeWarmup.errorCode == "runtime_busy")
        precondition(beforeWarmup.failedStage == .modelWarmup)
        precondition(beforeWarmupRuntime.requests.isEmpty)

        let beforeGenerationRuntime = HealthCheckFakeRuntime()
        beforeGenerationRuntime.responses = [response(ok: true, finalText: nil)]
        let beforeGeneration = await makeService(
            runtime: beforeGenerationRuntime,
            isRuntimeBusy: { !beforeGenerationRuntime.requests.isEmpty }
        ).run { _ in }
        precondition(beforeGeneration.errorCode == "runtime_busy")
        precondition(beforeGeneration.failedStage == .minimalGeneration)
        precondition(beforeGenerationRuntime.requests.map(\.command) == [.warmup])
    }

    private static func verifyWarmupRejectionStopsGeneration() async throws {
        let runtime = HealthCheckFakeRuntime()
        runtime.responses = [response(
            ok: false,
            finalText: nil,
            errorCode: "load_failed",
            errorMessage: "native loader rejected"
        )]
        let report = await makeService(runtime: runtime).run { _ in }

        precondition(!report.passed)
        precondition(report.failedStage == .modelWarmup)
        precondition(report.errorCode == "warmup_rejected")
        precondition(runtime.requests.map(\.command) == [.warmup])
        precondition(report.technicalDetail?.contains("native loader rejected") == true)
    }

    private static func verifyGenerationRejection() async throws {
        let runtime = HealthCheckFakeRuntime()
        runtime.responses = [
            response(ok: true, finalText: nil),
            response(
                ok: false,
                finalText: nil,
                errorCode: "generation_failed",
                errorMessage: "decoder rejected"
            ),
        ]
        let report = await makeService(runtime: runtime).run { _ in }

        precondition(!report.passed)
        precondition(report.failedStage == .minimalGeneration)
        precondition(report.errorCode == "generation_rejected")
        precondition(runtime.requests.count == 2)
    }

    private static func verifyEmptyGeneration() async throws {
        let runtime = HealthCheckFakeRuntime()
        runtime.responses = [
            response(ok: true, finalText: nil),
            response(ok: true, finalText: " \n "),
        ]
        let report = await makeService(runtime: runtime).run { _ in }

        precondition(!report.passed)
        precondition(report.failedStage == .minimalGeneration)
        precondition(report.errorCode == "generation_empty")
    }

    private static func verifyModelFailures() async throws {
        let runtime = HealthCheckFakeRuntime()
        let missing = await makeService(
            runtime: runtime,
            modelReadiness: { .missing }
        ).run { _ in }
        precondition(missing.failedStage == .modelIntegrity)
        precondition(missing.errorCode == "model_missing")

        let invalid = await makeService(
            runtime: runtime,
            modelReadiness: { .invalid("模型文件校验失败：model.safetensors") }
        ).run { _ in }
        precondition(invalid.failedStage == .modelIntegrity)
        precondition(invalid.errorCode == "model_integrity_failed")
        precondition(invalid.technicalDetail?.contains("model.safetensors") == true)
        precondition(runtime.requests.isEmpty)
    }

    private static func verifyRuntimeTransportFailure() async throws {
        let runtime = HealthCheckFakeRuntime()
        runtime.error = ManagedLLMRuntimeError.timedOut
        let report = await makeService(runtime: runtime).run { _ in }
        precondition(report.failedStage == .modelWarmup)
        precondition(report.errorCode == "runtime_timeout")
    }

    private static func verifyAtomicIdleRuntimeBusyMapping() async throws {
        let runtime = AtomicIdleFakeRuntime()
        let service = LocalModelHealthCheckService(dependencies: .init(
            runtimeProbe: {
                .success(pythonURL: URL(fileURLWithPath: "/managed/python3"))
            },
            modelReadiness: {
                .ready(URL(fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit"))
            },
            runtime: runtime,
            isRuntimeBusy: { false },
            modelDirectory: {
                URL(fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit")
            },
            diagnosticContext: {
                LocalModelHealthDiagnosticContext(
                    appVersion: "9.9.9",
                    appBuild: "999",
                    operatingSystem: "macOS Test",
                    modelID: "typewhale-qwen3-4b-instruct-2507-4bit"
                )
            },
            now: { ProcessInfo.processInfo.systemUptime }
        ))

        let report = await service.run { _ in }

        precondition(report.errorCode == "runtime_busy")
        precondition(report.failedStage == .modelWarmup)
        precondition(runtime.idlePerformCount == 1)
        precondition(runtime.regularPerformCount == 0)
    }

    private static func verifyCancellationDoesNotReachWorker() async throws {
        let runtime = HealthCheckFakeRuntime()
        let service = makeService(
            runtime: runtime,
            runtimeProbe: {
                Thread.sleep(forTimeInterval: 0.1)
                return .success(pythonURL: URL(fileURLWithPath: "/managed/python3"))
            }
        )
        let task = Task {
            await service.run { _ in }
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        let report = await task.value

        precondition(report.errorCode == "runtime_cancelled")
        precondition(report.failedStage == .runtimeImport)
        precondition(runtime.requests.isEmpty)
    }

    private static func makeService(
        runtime: HealthCheckFakeRuntime,
        runtimeProbe: @escaping () -> ManagedMLXRuntimeProbeResult = {
            .success(pythonURL: URL(fileURLWithPath: "/managed/python3"))
        },
        modelReadiness: @escaping () -> ManagedLLMReadiness = {
            .ready(URL(fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit"))
        },
        isRuntimeBusy: @escaping () -> Bool = { false },
        now: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) -> LocalModelHealthCheckService {
        LocalModelHealthCheckService(dependencies: .init(
            runtimeProbe: runtimeProbe,
            modelReadiness: modelReadiness,
            runtime: runtime,
            isRuntimeBusy: isRuntimeBusy,
            modelDirectory: {
                URL(fileURLWithPath: "/managed/qwen3-4b-instruct-2507-4bit")
            },
            diagnosticContext: {
                LocalModelHealthDiagnosticContext(
                    appVersion: "9.9.9",
                    appBuild: "999",
                    operatingSystem: "macOS Test",
                    modelID: "typewhale-qwen3-4b-instruct-2507-4bit"
                )
            },
            now: now
        ))
    }

    private static func response(
        ok: Bool,
        finalText: String?,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metrics: ManagedLLMMetrics? = nil
    ) -> ManagedMLXLLMResponse {
        ManagedMLXLLMResponse(
            protocolVersion: 1,
            id: "placeholder",
            ok: ok,
            finalText: finalText,
            errorCode: errorCode,
            errorMessage: errorMessage,
            metrics: metrics,
            cancelled: false
        )
    }

    private static func metrics(loadMS: Double) -> ManagedLLMMetrics {
        ManagedLLMMetrics(
            loadMS: loadMS,
            ttftMS: 4,
            completionMS: 6,
            tokensPerSecond: 20,
            peakRSSBytes: 3_000_000_000,
            promptTokens: 8,
            completionTokens: 2
        )
    }
}
