import Foundation

final class OllamaRewriteEngine: SmartAITextEngine {
    private let endpoint: URL
    private let model: SmartAIModel
    private let session: URLSession
    let displayName: String
    let logName = "ollama"
    let usesLocalCostGuard = false

    init(
        model: SmartAIModel = .ollamaQwen35B,
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.endpoint = endpoint
        self.session = session
        self.displayName = model.displayName
    }

    static func warmUp(
        model: SmartAIModel,
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
        session: URLSession = .shared,
        reason: String
    ) async {
        guard model.provider == .ollama else { return }
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
                model: model.engineModelName,
                messages: [
                    OllamaMessage(role: "system", content: "只输出 OK。"),
                    OllamaMessage(role: "user", content: "OK")
                ],
                stream: false,
                think: false,
                keepAlive: "30m",
                options: OllamaChatOptions(
                    temperature: 0.0,
                    topP: 0.9,
                    numPredict: 2
                )
            ))
            LaunchDiagnostics.mark("ollama warmup_start reason=\(reason) model=\(model.engineModelName)")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                LaunchDiagnostics.mark(
                    "ollama warmup_failed reason=\(reason) model=\(model.engineModelName) http_status=\(status) body=\"\(logSnippet(body))\""
                )
                return
            }
            let decoded = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
            LaunchDiagnostics.mark(
                "ollama warmup_done reason=\(reason) model=\(model.engineModelName) prompt_eval_count=\(decoded?.promptEvalCount ?? -1) eval_count=\(decoded?.evalCount ?? -1) total_duration_ns=\(decoded?.totalDuration ?? -1)"
            )
        } catch {
            LaunchDiagnostics.mark(
                "ollama warmup_failed reason=\(reason) model=\(model.engineModelName) error=\"\(logSnippet(error.localizedDescription))\""
            )
        }
    }

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext,
        preference: SmartRewritePreference
    ) async throws -> SmartRewriteEngineOutput {
        guard model.provider == .ollama else {
            throw OllamaRewriteError.unsupportedModel(model.rawValue)
        }
        let prompt = SmartRewritePromptBuilder.prompt(
            rawText: rawText,
            mode: mode,
            context: context,
            preference: preference
        )
        return try await complete(
            prompt: prompt,
            systemPrompt: rewriteSystemPrompt,
            mode: mode.displayName,
            triggeredBy: "final_smart_rewrite",
            rawTextLength: rawText.count,
            context: context
        )
    }

    func translate(
        rawText: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String = "final_translation"
    ) async throws -> SmartTranslationOutput {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw OllamaRewriteError.emptyContent
        }
        let prompt = SmartTranslationPromptBuilder.prompt(
            source: source,
            direction: direction,
            context: context,
            triggeredBy: triggeredBy
        )
        let translated = try await complete(
            prompt: prompt,
            systemPrompt: translationSystemPrompt,
            mode: direction.displayName,
            triggeredBy: triggeredBy,
            rawTextLength: source.count,
            context: context
        )
        return SmartTranslationOutput(
            sourceText: source,
            translatedText: translated.text,
            direction: direction,
            modelName: displayName,
            usage: nil
        )
    }

    private var rewriteSystemPrompt: String {
        """
        你是 TypeWhale 的本地语音文本整理层，只整理原始语音文本，不回答、不执行、不扩写知识。
        如果原文说“帮我回答”“告诉用户”“你就说”，不要改成直接对最终用户说话；只整理成用户要表达的意图或待办。
        合格示例：回复用户退订会员咨询：请引导其打开设置，点击订阅选项后取消，并安抚对方无需担忧。
        不合格示例：您可以打开设置，点击订阅，然后取消，请不用担心。
        忠实保留叙述主体；原文没有明确说“对方、客户、用户、团队、他、她”时，不要主动补出这些主体。
        不要为了结构完整而补“无明确行动项”或泛化风险。
        主体不明参考：原文“没有准确理解并妥善处理我表达的内容，而且沟通里还有曲解。”合格输出“我的表达内容没有被准确理解和妥善处理，沟通中还存在曲解。”不合格输出“对方未准确理解并妥善处理我表达的内容，且在沟通中存在曲解。”
        保持输入主要语言，只输出最终正文，不输出分析、标签、Markdown 或规则解释。
        """
    }

    private var translationSystemPrompt: String {
        """
        你是 TypeWhale 的本地快速语音翻译层，使用非推理模式工作。
        严格按照用户指定方向翻译。只输出最终译文，不要输出分析、思考、Markdown 代码块、标签或解释。
        """
    }

    private func complete(
        prompt: String,
        systemPrompt: String,
        mode: String,
        triggeredBy: String,
        rawTextLength: Int,
        context: SmartInputContext
    ) async throws -> SmartRewriteEngineOutput {
        let requestID = UUID().uuidString
        let messages = [
            OllamaMessage(role: "system", content: systemPrompt),
            OllamaMessage(role: "user", content: prompt)
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: model.engineModelName,
            messages: messages,
            stream: false,
            think: false,
            keepAlive: "30m",
            options: OllamaChatOptions(
                temperature: 0.1,
                topP: 0.9,
                numPredict: SmartRewriteCostGuard.maxOutputTokens
            )
        ))
        LaunchDiagnostics.mark(
            "ollama request_start recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(requestID) triggered_by=\(triggeredBy) model=\(model.engineModelName) mode=\(mode) rawText_length=\(rawTextLength) prompt_length=\(systemPrompt.count + prompt.count)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            LaunchDiagnostics.mark(
                "ollama request_failed recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(requestID) triggered_by=\(triggeredBy) model=\(model.engineModelName) mode=\(mode) error=\"\(Self.logSnippet(error.localizedDescription))\""
            )
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            LaunchDiagnostics.mark(
                "ollama request_failed recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(requestID) triggered_by=\(triggeredBy) model=\(model.engineModelName) mode=\(mode) error=invalid_response"
            )
            throw OllamaRewriteError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            LaunchDiagnostics.mark(
                "ollama request_failed recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(requestID) triggered_by=\(triggeredBy) model=\(model.engineModelName) mode=\(mode) http_status=\(httpResponse.statusCode) body=\"\(Self.logSnippet(body))\""
            )
            throw OllamaRewriteError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let content = SmartRewriteOutputSanitizer.cleanLocalModel(
            decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !content.isEmpty else {
            throw OllamaRewriteError.emptyContent
        }
        LaunchDiagnostics.mark(
            "ollama request_done recording_session_id=\(context.recordingSessionId ?? "--") request_id=\(requestID) triggered_by=\(triggeredBy) model=\(model.engineModelName) mode=\(mode) prompt_eval_count=\(decoded.promptEvalCount ?? -1) eval_count=\(decoded.evalCount ?? -1) total_duration_ns=\(decoded.totalDuration ?? -1)"
        )
        return SmartRewriteEngineOutput(text: content, usage: nil)
    }

    private static func logSnippet(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum OllamaRewriteError: Error {
    case unsupportedModel(String)
    case invalidResponse
    case httpStatus(Int)
    case emptyContent
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let think: Bool
    let keepAlive: String
    let options: OllamaChatOptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case think
        case keepAlive = "keep_alive"
        case options
    }
}

private struct OllamaChatOptions: Encodable {
    let temperature: Double
    let topP: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
    }
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaChatResponse: Decodable {
    let message: OllamaMessage
    let totalDuration: Int?
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case totalDuration = "total_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}
