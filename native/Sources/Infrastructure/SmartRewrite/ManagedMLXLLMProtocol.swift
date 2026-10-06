import Foundation

enum ManagedMLXLLMCommand: String, Codable {
    case warmup
    case rewrite
    case translate
    case health
}

enum ManagedLLMReasoning: String, Codable {
    case low
}

struct ManagedMLXLLMRequest: Codable, Equatable {
    let protocolVersion: Int
    let id: String
    let command: ManagedMLXLLMCommand
    let modelDirectory: String
    let systemPrompt: String
    let userPrompt: String
    let reasoning: ManagedLLMReasoning
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case id
        case command
        case modelDirectory = "model_directory"
        case systemPrompt = "system_prompt"
        case userPrompt = "user_prompt"
        case reasoning
        case maxTokens = "max_tokens"
    }
}

struct ManagedLLMMetrics: Codable, Equatable {
    let loadMS: Double?
    let ttftMS: Double?
    let completionMS: Double?
    let tokensPerSecond: Double?
    let peakRSSBytes: Int64?
    let promptTokens: Int?
    let completionTokens: Int?
    let promptCacheHit: Bool?
    let promptCacheReusedTokens: Int?
    let promptTokensEvaluated: Int?

    init(
        loadMS: Double?,
        ttftMS: Double?,
        completionMS: Double?,
        tokensPerSecond: Double?,
        peakRSSBytes: Int64?,
        promptTokens: Int?,
        completionTokens: Int?,
        promptCacheHit: Bool? = nil,
        promptCacheReusedTokens: Int? = nil,
        promptTokensEvaluated: Int? = nil
    ) {
        self.loadMS = loadMS
        self.ttftMS = ttftMS
        self.completionMS = completionMS
        self.tokensPerSecond = tokensPerSecond
        self.peakRSSBytes = peakRSSBytes
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.promptCacheHit = promptCacheHit
        self.promptCacheReusedTokens = promptCacheReusedTokens
        self.promptTokensEvaluated = promptTokensEvaluated
    }

    enum CodingKeys: String, CodingKey {
        case loadMS = "load_ms"
        case ttftMS = "ttft_ms"
        case completionMS = "completion_ms"
        case tokensPerSecond = "tokens_per_second"
        case peakRSSBytes = "peak_rss_bytes"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptCacheHit = "prompt_cache_hit"
        case promptCacheReusedTokens = "prompt_cache_reused_tokens"
        case promptTokensEvaluated = "prompt_tokens_evaluated"
    }
}

struct ManagedMLXLLMResponse: Codable, Equatable {
    let protocolVersion: Int
    let id: String
    let ok: Bool
    let finalText: String?
    let errorCode: String?
    let errorMessage: String?
    let metrics: ManagedLLMMetrics?
    let cancelled: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case id
        case ok
        case finalText = "final_text"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case metrics
        case cancelled
    }

    static func cancelled(id: String) -> ManagedMLXLLMResponse {
        ManagedMLXLLMResponse(
            protocolVersion: 1,
            id: id,
            ok: false,
            finalText: nil,
            errorCode: "cancelled",
            errorMessage: "请求已取消",
            metrics: nil,
            cancelled: true
        )
    }
}
