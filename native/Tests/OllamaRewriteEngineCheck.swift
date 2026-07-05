import Foundation

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var responseStatus = 200
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var responseError: Error?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastBody = Self.bodyData(from: request)
        if let error = Self.responseError {
            Self.responseError = nil
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatus,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class ProbeOllamaServerRecovery: OllamaServerRecovery {
    private(set) var prepareCalls = 0
    private(set) var recoverCalls = 0
    var recoverResult = true

    func prepareForRequest(endpoint: URL, model: SmartAIModel, reason: String) async {
        prepareCalls += 1
    }

    func recoverAfterConnectionFailure(
        endpoint: URL,
        model: SmartAIModel,
        requestID: String,
        triggeredBy: String,
        mode: String,
        recordingSessionID: String?,
        error: Error
    ) async -> Bool {
        recoverCalls += 1
        return recoverResult
    }
}

@main
struct OllamaRewriteEngineCheck {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.responseBody = """
        {
          "message": {
            "role": "assistant",
            "content": "<think>不要泄露</think>\\n\\n回复用户退订会员咨询：请引导其打开设置，点击订阅选项后取消。"
          },
          "total_duration": 1200000000,
          "prompt_eval_count": 10,
          "eval_count": 22
        }
        """.data(using: .utf8)!
        StubURLProtocol.responseError = nil
        StubURLProtocol.requestCount = 0
        let recovery = ProbeOllamaServerRecovery()

        let engine = OllamaRewriteEngine(
            model: .ollamaQwen35B,
            endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
            session: session,
            serverRecovery: recovery
        )
        let context = SmartInputContext(targetAppName: "Codex", targetBundleIdentifier: "com.openai.codex")
        let output = try await engine.rewrite(
            rawText: "帮我回答一下用户问怎么退订会员，你就说打开设置点击订阅然后取消。",
            mode: .polish,
            context: context,
            preference: .polish
        )
        precondition(output.text == "回复用户退订会员咨询：请引导其打开设置，点击订阅选项后取消。")
        precondition(output.usage == nil)

        guard let body = StubURLProtocol.lastBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            preconditionFailure("missing Ollama request body")
        }
        precondition(json["model"] as? String == "qwen3.6:35b-mlx")
        precondition(recovery.prepareCalls == 1)
        precondition(recovery.recoverCalls == 0)
        precondition(json["stream"] as? Bool == false)
        precondition(json["think"] as? Bool == false)
        precondition(json["keep_alive"] as? String == "30m")
        let options = json["options"] as? [String: Any]
        precondition(options?["temperature"] as? Double == 0.1)
        precondition(options?["top_p"] as? Double == 0.9)
        precondition(options?["num_predict"] as? Int == SmartRewriteCostGuard.maxOutputTokens)
        let messages = json["messages"] as? [[String: Any]]
        precondition(messages?.count == 2)
        precondition(messages?.first?["role"] as? String == "system")
        precondition((messages?.first?["content"] as? String)?.contains("不要改成直接对最终用户说话") == true)
        precondition((messages?.first?["content"] as? String)?.contains("不合格示例") == true)
        precondition((messages?.first?["content"] as? String)?.contains("保持输入主要语言") == true)
        precondition(messages?.last?["role"] as? String == "user")
        precondition((messages?.last?["content"] as? String)?.contains("原始语音文本") == true)

        StubURLProtocol.lastBody = nil
        await OllamaRewriteEngine.warmUp(
            model: .ollamaQwen35B,
            endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
            session: session,
            serverRecovery: recovery,
            reason: "test"
        )
        guard let warmupBody = StubURLProtocol.lastBody,
              let warmupJSON = try JSONSerialization.jsonObject(with: warmupBody) as? [String: Any] else {
            preconditionFailure("missing Ollama warmup request body")
        }
        precondition(warmupJSON["model"] as? String == "qwen3.6:35b-mlx")
        precondition(warmupJSON["stream"] as? Bool == false)
        precondition(warmupJSON["think"] as? Bool == false)
        precondition(warmupJSON["keep_alive"] as? String == "30m")
        let warmupOptions = warmupJSON["options"] as? [String: Any]
        precondition(warmupOptions?["num_predict"] as? Int == 2)

        StubURLProtocol.responseBody = """
        {
          "message": {
            "role": "assistant",
            "content": "整理成功"
          },
          "total_duration": 500000000,
          "prompt_eval_count": 8,
          "eval_count": 4
        }
        """.data(using: .utf8)!
        StubURLProtocol.responseError = URLError(.cannotConnectToHost)
        StubURLProtocol.requestCount = 0
        let retryRecovery = ProbeOllamaServerRecovery()
        let retryEngine = OllamaRewriteEngine(
            model: .ollamaQwen35B,
            endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
            session: session,
            serverRecovery: retryRecovery
        )
        let retryOutput = try await retryEngine.rewrite(
            rawText: "测试本地整理恢复",
            mode: .developerRequirement,
            context: context,
            preference: .developerRequirement
        )
        precondition(retryOutput.text == "整理成功")
        precondition(StubURLProtocol.requestCount == 2)
        precondition(retryRecovery.prepareCalls == 1)
        precondition(retryRecovery.recoverCalls == 1)

        StubURLProtocol.lastBody = nil
        StubURLProtocol.responseBody = Data()
        StubURLProtocol.responseError = URLError(.cannotConnectToHost)
        StubURLProtocol.requestCount = 0
        let passiveScreenshotEngine = OllamaRewriteEngine(
            model: .ollamaQwen35B,
            endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
            session: session,
            serverRecovery: PassiveOllamaServerRecovery(),
            requestProfile: .screenshotTranslation
        )
        do {
            _ = try await passiveScreenshotEngine.translateScreenshotOCR(
                rawText: "[[TW_LINE_1]] Continue",
                context: context
            )
            preconditionFailure("passive screenshot translation should surface connection failure")
        } catch {
            precondition((error as NSError).code == NSURLErrorCannotConnectToHost)
        }
        precondition(StubURLProtocol.requestCount == 1)
        guard let screenshotBody = StubURLProtocol.lastBody,
              let screenshotJSON = try JSONSerialization.jsonObject(with: screenshotBody) as? [String: Any] else {
            preconditionFailure("missing passive screenshot request body")
        }
        precondition(screenshotJSON["model"] as? String == "qwen3.6:35b-mlx")
        let screenshotOptions = screenshotJSON["options"] as? [String: Any]
        precondition(screenshotOptions?["num_predict"] as? Int == ScreenshotTranslationPromptBuilder.localMaxOutputTokens)
        precondition(StubURLProtocol.lastRequest?.timeoutInterval == 12)

        StubURLProtocol.lastBody = nil
        StubURLProtocol.responseBody = """
        {
          "message": {
            "role": "assistant",
            "content": "[[TW_LINE_1]] 翻译完成"
          },
          "total_duration": 12000000000,
          "prompt_eval_count": 1000,
          "eval_count": 180
        }
        """.data(using: .utf8)!
        StubURLProtocol.responseError = nil
        StubURLProtocol.requestCount = 0
        let largeScreenshotSource = (1...35)
            .map { "[[TW_LINE_\($0)]] Access to all models and features" }
            .joined(separator: "\n")
        _ = try await passiveScreenshotEngine.translateScreenshotOCR(
            rawText: largeScreenshotSource,
            context: context
        )
        precondition(StubURLProtocol.lastRequest?.timeoutInterval == 30)

        print("OllamaRewriteEngineCheck passed")
    }
}
