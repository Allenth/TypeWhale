import Foundation

@main
struct ManagedLLMResponseValidatorCheck {
    static func main() throws {
        let validWarmup = response(ok: true, finalText: nil)
        let warmupText = try ManagedLLMResponseValidator.validate(
            validWarmup,
            requireFinalText: false
        )
        precondition(warmupText == nil)

        let validGeneration = response(ok: true, finalText: "  正常  ")
        let generationText = try ManagedLLMResponseValidator.validate(
            validGeneration,
            requireFinalText: true
        )
        precondition(generationText == "正常")

        assertError(
            response(protocolVersion: 2, ok: true, finalText: "text"),
            requireFinalText: true,
            expected: .invalidProtocol
        )
        assertError(
            response(ok: false, finalText: nil, cancelled: true),
            requireFinalText: false,
            expected: .cancelled
        )
        assertError(
            response(
                ok: false,
                finalText: nil,
                errorCode: "load_failed",
                errorMessage: "model load failed"
            ),
            requireFinalText: false,
            expected: .rejected(code: "load_failed", message: "model load failed")
        )
        assertError(
            response(ok: true, finalText: " \n "),
            requireFinalText: true,
            expected: .emptyFinalText
        )

        print("ManagedLLMResponseValidatorCheck passed")
    }

    private static func assertError(
        _ response: ManagedMLXLLMResponse,
        requireFinalText: Bool,
        expected: ManagedLLMResponseValidationError
    ) {
        do {
            _ = try ManagedLLMResponseValidator.validate(
                response,
                requireFinalText: requireFinalText
            )
            preconditionFailure("expected response validation to fail")
        } catch let error as ManagedLLMResponseValidationError {
            precondition(error == expected)
        } catch {
            preconditionFailure("unexpected error: \(error)")
        }
    }

    private static func response(
        protocolVersion: Int = 1,
        ok: Bool,
        finalText: String?,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        cancelled: Bool = false
    ) -> ManagedMLXLLMResponse {
        ManagedMLXLLMResponse(
            protocolVersion: protocolVersion,
            id: "response-validator-check",
            ok: ok,
            finalText: finalText,
            errorCode: errorCode,
            errorMessage: errorMessage,
            metrics: nil,
            cancelled: cancelled
        )
    }
}
