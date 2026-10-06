import Foundation

struct ManagedLLMGenerationProfile: Equatable {
    let maxOutputTokens: Int

    static let standard = ManagedLLMGenerationProfile(maxOutputTokens: 2_048)
}

enum TypeWhaleLocalLLMError: Error, LocalizedError {
    case emptyContent
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "待处理文本为空"
        case .invalidResponse:
            return "本地模型未返回有效最终文本"
        case .requestFailed(let message):
            return message
        }
    }
}

final class TypeWhaleLocalLLMEngine: SmartAITextEngine, ScreenshotTranslationEngine {
    let displayName = "本地直驱 Qwen3 4B Instruct"
    let logName = "managed_mlx"
    let usesLocalCostGuard = false

    private let modelID: ManagedLLMModelID
    private let runtime: ManagedLLMRuntime
    private let modelDirectory: () -> URL
    private let generationProfile: ManagedLLMGenerationProfile

    init(
        modelID: ManagedLLMModelID,
        runtime: ManagedLLMRuntime,
        modelDirectory: @escaping () -> URL,
        generationProfile: ManagedLLMGenerationProfile = .standard
    ) {
        self.modelID = modelID
        self.runtime = runtime
        self.modelDirectory = modelDirectory
        self.generationProfile = generationProfile
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw TypeWhaleLocalLLMError.emptyContent }
        let prompt = SmartRewritePromptBuilder.prompt(
            rawText: source,
            mode: mode,
            context: context,
            preference: preference
        )
        let finalText = try await complete(
            command: .rewrite,
            systemPrompt: ManagedLLMPrefill.rewriteSystemPrompt,
            userPrompt: prompt,
            triggeredBy: "final_smart_rewrite",
            context: context
        )
        let cleaned = SmartRewriteOutputSanitizer.cleanLocalModel(finalText)
        guard !cleaned.isEmpty else { throw TypeWhaleLocalLLMError.invalidResponse }
        return SmartRewriteEngineOutput(text: cleaned, usage: nil)
    }

    func translate(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String = "final_translation"
    ) async throws -> SmartTranslationOutput {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw TypeWhaleLocalLLMError.emptyContent }
        let prompt = SmartTranslationPromptBuilder.prompt(
            source: source,
            direction: direction,
            context: context,
            triggeredBy: triggeredBy
        )
        let finalText = try await complete(
            command: .translate,
            systemPrompt: SmartRewriteSafetyPrompt.translationSystemPrompt(
                lead: "你是 TypeWhale 的本地语音翻译层，只执行翻译并直接给出译文。"
            ),
            userPrompt: prompt,
            triggeredBy: triggeredBy,
            context: context
        )
        let translated = SmartRewriteOutputSanitizer.cleanTranslation(finalText)
        guard !translated.isEmpty else { throw TypeWhaleLocalLLMError.invalidResponse }
        return SmartTranslationOutput(
            sourceText: source,
            translatedText: translated,
            direction: direction,
            modelName: displayName,
            usage: nil
        )
    }

    func translateScreenshotOCR(
        rawText: String,
        context: SmartInputContext
    ) async throws -> SmartTranslationOutput {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw TypeWhaleLocalLLMError.emptyContent }
        let finalText = try await complete(
            command: .translate,
            systemPrompt: ScreenshotTranslationPromptBuilder.systemPrompt(
                lead: "你是 TypeWhale 的本地截图 OCR 英译中层，只执行逐行翻译并直接给出译文。"
            ),
            userPrompt: ScreenshotTranslationPromptBuilder.prompt(
                source: source,
                context: context
            ),
            triggeredBy: ScreenshotTranslationPromptBuilder.triggeredBy,
            context: context,
            maxOutputTokens: ScreenshotTranslationPromptBuilder.localMaxOutputTokens
        )
        let translated = SmartRewriteOutputSanitizer.cleanTranslation(finalText)
        guard !translated.isEmpty else { throw TypeWhaleLocalLLMError.invalidResponse }
        return SmartTranslationOutput(
            sourceText: source,
            translatedText: translated,
            direction: .englishToChinese,
            modelName: displayName,
            usage: nil
        )
    }

    private func complete(
        command: ManagedMLXLLMCommand,
        systemPrompt: String,
        userPrompt: String,
        triggeredBy: String,
        context: SmartInputContext,
        maxOutputTokens: Int? = nil
    ) async throws -> String {
        let request = ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: UUID().uuidString,
            command: command,
            modelDirectory: modelDirectory().path,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            reasoning: .low,
            maxTokens: maxOutputTokens ?? generationProfile.maxOutputTokens
        )
        LaunchDiagnostics.mark(
            "managed_mlx request_start recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(request.id) triggered_by=\(triggeredBy) model=\(modelID.rawValue) prompt_length=\(systemPrompt.count + userPrompt.count)"
        )

        do {
            let response = try await runtime.perform(request)
            guard response.protocolVersion == 1 else {
                throw TypeWhaleLocalLLMError.invalidResponse
            }
            if response.cancelled {
                throw ManagedLLMRuntimeError.cancelled
            }
            guard response.ok else {
                throw TypeWhaleLocalLLMError.requestFailed(
                    response.errorMessage ?? "本地模型请求失败"
                )
            }
            guard let finalText = response.finalText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !finalText.isEmpty else {
                throw TypeWhaleLocalLLMError.invalidResponse
            }
            let metrics = response.metrics
            LaunchDiagnostics.mark(
                "managed_mlx request_done recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(request.id) triggered_by=\(triggeredBy) model=\(modelID.rawValue) ttft_ms=\(metrics?.ttftMS ?? -1) completion_ms=\(metrics?.completionMS ?? -1) tokens_per_second=\(metrics?.tokensPerSecond ?? -1) peak_rss_bytes=\(metrics?.peakRSSBytes ?? -1) prompt_cache_hit=\(metrics?.promptCacheHit ?? false) prompt_cache_reused_tokens=\(metrics?.promptCacheReusedTokens ?? 0) prompt_tokens_evaluated=\(metrics?.promptTokensEvaluated ?? metrics?.promptTokens ?? -1)"
            )
            return finalText
        } catch {
            LaunchDiagnostics.mark(
                "managed_mlx request_failed recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(request.id) triggered_by=\(triggeredBy) model=\(modelID.rawValue) error_type=\(String(describing: type(of: error)))"
            )
            throw error
        }
    }
}

final class ManagedLLMRuntimeService {
    static let shared = ManagedLLMRuntimeService()

    let runtimeState: ManagedMLXRuntimeState
    let runtime: ManagedLLMRuntime
    let registry: ManagedLLMModelRegistry
    let runtimeLocator: ManagedMLXRuntimeLocator

    private init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(AppBrand.supportDirectoryName, isDirectory: true)
        let runtimesRoot = applicationSupport.appendingPathComponent("Runtimes", isDirectory: true)
        let modelsRoot = applicationSupport
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("LLM", isDirectory: true)
        registry = ManagedLLMModelRegistry(rootURL: modelsRoot)

        runtimeLocator = ManagedMLXRuntimeLocator(runtimesRootURL: runtimesRoot)
        let locatedState = runtimeLocator.state
        guard case .ready(let pythonURL) = locatedState else {
            runtimeState = locatedState
            runtime = UnavailableManagedLLMRuntime()
            return
        }
        guard let resources = bundle.resourceURL else {
            runtimeState = .invalid("应用资源目录不可用")
            runtime = UnavailableManagedLLMRuntime()
            return
        }
        let workerURL = resources.appendingPathComponent("managed_mlx_llm_worker.py")
        guard fileManager.fileExists(atPath: workerURL.path) else {
            runtimeState = .invalid("本地模型 Worker 缺失")
            runtime = UnavailableManagedLLMRuntime()
            return
        }
        runtimeState = .ready(pythonURL)
        runtime = ManagedMLXLLMRuntime(
            pythonURL: pythonURL,
            workerURL: workerURL
        )
    }

    func engine(for modelID: ManagedLLMModelID) -> SmartAITextEngine {
        TypeWhaleLocalLLMEngine(
            modelID: modelID,
            runtime: runtime,
            modelDirectory: { [registry] in registry.modelDirectory(for: modelID) }
        )
    }

    func screenshotEngine(for modelID: ManagedLLMModelID) -> ScreenshotTranslationEngine {
        TypeWhaleLocalLLMEngine(
            modelID: modelID,
            runtime: runtime,
            modelDirectory: { [registry] in registry.modelDirectory(for: modelID) }
        )
    }

    func makeLocalModelHealthCheckService(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> LocalModelHealthCheckService {
        let modelID = ManagedLLMModelID.qwen3_4BInstruct2507_4bit
        return LocalModelHealthCheckService(dependencies: .init(
            runtimeProbe: { [runtimeLocator] in
                runtimeLocator.probe()
            },
            modelReadiness: { [registry] in
                registry.readiness(for: modelID)
            },
            runtime: runtime,
            isRuntimeBusy: { [runtime] in
                (runtime as? ManagedLLMRuntimeActivityReporting)?.hasActiveRequest ?? false
            },
            modelDirectory: { [registry] in
                registry.modelDirectory(for: modelID)
            },
            diagnosticContext: {
                let info = bundle.infoDictionary
                return LocalModelHealthDiagnosticContext(
                    appVersion: info?["CFBundleShortVersionString"] as? String ?? "--",
                    appBuild: info?["CFBundleVersion"] as? String ?? "--",
                    operatingSystem: processInfo.operatingSystemVersionString,
                    modelID: modelID.rawValue
                )
            },
            now: {
                processInfo.systemUptime
            },
            log: { message in
                LaunchDiagnostics.mark(message)
            }
        ))
    }

    struct WorkerMemorySnapshot {
        let processID: pid_t?
        let footprintMB: Int

        var isRunning: Bool { processID != nil }
    }

    var workerMemorySnapshot: WorkerMemorySnapshot {
        let processID = (runtime as? ManagedMLXLLMRuntime)?
            .ownedProcessIdentifier
        let footprintMB = processID.map {
            Int(
                MemoryMonitor.footprintBytes(processID: $0)
                    / UInt64(1024 * 1024)
            )
        } ?? 0
        return WorkerMemorySnapshot(
            processID: processID,
            footprintMB: footprintMB
        )
    }

    func stop() {
        runtime.stop()
    }
}

private final class UnavailableManagedLLMRuntime: ManagedLLMRuntime {
    func perform(_ request: ManagedMLXLLMRequest) async throws -> ManagedMLXLLMResponse {
        _ = request
        throw ManagedLLMRuntimeError.unavailable
    }

    func cancelCurrentRequest() {}
    func stop() {}
}
