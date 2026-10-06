import Foundation

enum ManagedLLMResponseValidationError: Error, Equatable, LocalizedError {
    case invalidProtocol
    case cancelled
    case rejected(code: String?, message: String?)
    case emptyFinalText

    var errorDescription: String? {
        switch self {
        case .invalidProtocol:
            return "本地模型响应协议不兼容"
        case .cancelled:
            return "本地模型请求已取消"
        case .rejected(_, let message):
            return message ?? "本地模型拒绝了请求"
        case .emptyFinalText:
            return "本地模型没有返回有效正文"
        }
    }
}

enum ManagedLLMResponseValidator {
    static func validate(
        _ response: ManagedMLXLLMResponse,
        requireFinalText: Bool
    ) throws -> String? {
        guard response.protocolVersion == 1 else {
            throw ManagedLLMResponseValidationError.invalidProtocol
        }
        guard !response.cancelled else {
            throw ManagedLLMResponseValidationError.cancelled
        }
        guard response.ok else {
            throw ManagedLLMResponseValidationError.rejected(
                code: response.errorCode,
                message: response.errorMessage
            )
        }
        let finalText = response.finalText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if requireFinalText, finalText?.isEmpty != false {
            throw ManagedLLMResponseValidationError.emptyFinalText
        }
        return finalText
    }
}
