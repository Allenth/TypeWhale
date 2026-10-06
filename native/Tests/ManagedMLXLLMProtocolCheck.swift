import Foundation

@main
struct ManagedMLXLLMProtocolCheck {
    static func main() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        let request = ManagedMLXLLMRequest(
            protocolVersion: 1,
            id: "fixture-request",
            command: .rewrite,
            modelDirectory: "/managed/model",
            systemPrompt: "system",
            userPrompt: "user",
            reasoning: .low,
            maxTokens: 256
        )
        let requestData = try encoder.encode(request)
        let decodedRequest = try decoder.decode(ManagedMLXLLMRequest.self, from: requestData)
        precondition(decodedRequest == request)

        let metrics = ManagedLLMMetrics(
            loadMS: 1_658.5,
            ttftMS: 473.7,
            completionMS: 1_146.5,
            tokensPerSecond: 121.6,
            peakRSSBytes: 13_046_824_960,
            promptTokens: 123,
            completionTokens: 45,
            promptCacheHit: true,
            promptCacheReusedTokens: 100,
            promptTokensEvaluated: 23
        )
        let response = ManagedMLXLLMResponse(
            protocolVersion: 1,
            id: "fixture-request",
            ok: true,
            finalText: "最终正文",
            errorCode: nil,
            errorMessage: nil,
            metrics: metrics,
            cancelled: false
        )
        let responseData = try encoder.encode(response)
        let decodedResponse = try decoder.decode(ManagedMLXLLMResponse.self, from: responseData)
        precondition(decodedResponse == response)
        precondition(decodedResponse.metrics?.promptCacheHit == true)
        precondition(decodedResponse.metrics?.promptCacheReusedTokens == 100)
        precondition(decodedResponse.metrics?.promptTokensEvaluated == 23)

        let legacyResponse = try decoder.decode(
            ManagedMLXLLMResponse.self,
            from: Data(
                """
                {
                  "protocol_version": 1,
                  "id": "legacy-worker",
                  "ok": true,
                  "final_text": "兼容旧 Worker",
                  "error_code": null,
                  "error_message": null,
                  "metrics": {
                    "load_ms": 100,
                    "ttft_ms": 200,
                    "completion_ms": 300,
                    "tokens_per_second": 50,
                    "peak_rss_bytes": 1000,
                    "prompt_tokens": 10,
                    "completion_tokens": 2
                  },
                  "cancelled": false
                }
                """.utf8
            )
        )
        precondition(legacyResponse.metrics?.promptCacheHit == nil)
        precondition(legacyResponse.metrics?.promptCacheReusedTokens == nil)
        precondition(legacyResponse.metrics?.promptTokensEvaluated == nil)

        let cancelled = ManagedMLXLLMResponse.cancelled(id: "cancelled-request")
        precondition(cancelled.cancelled)
        precondition(!cancelled.ok)
        precondition(cancelled.finalText == nil)

        let forbidden = ["analysis", "thinking", "rawTokens", "raw_tokens", "rawOutput", "raw_output"]
        for data in [requestData, responseData, try encoder.encode(cancelled)] {
            let object = try JSONSerialization.jsonObject(with: data)
            let keys = collectKeys(object)
            precondition(forbidden.allSatisfy { !keys.contains($0) })
        }

        print("ManagedMLXLLMProtocolCheck passed")
    }

    private static func collectKeys(_ value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return Set(dictionary.keys).union(dictionary.values.flatMap { collectKeys($0) })
        }
        if let array = value as? [Any] {
            return Set(array.flatMap { collectKeys($0) })
        }
        return []
    }
}
