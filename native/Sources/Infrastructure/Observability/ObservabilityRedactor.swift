import Foundation

/// 参数脱敏：把 ObservabilityValue 拍平成字符串字典，并对疑似自由文本兜底脱敏。
/// 这是「绝不上传用户内容」红线的最后一道运行时防线（见 docs/埋点方案.md §5/§6）。
enum ObservabilityRedactor {
    /// 受控 token 允许的字符集（小写/大写/数字/`_-.`）。
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
    )
    /// 超过此长度或含非白名单字符（空格、换行、中文等）→ 视为疑似用户内容。
    private static let maxTokenLength = 40

    static func sanitizeToken(_ raw: String) -> String {
        guard raw.count <= maxTokenLength,
              raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "redacted"
        }
        return raw
    }

    /// 把白名单参数拍平成可上报的字符串字典。
    static func flatten(_ params: [String: ObservabilityValue]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(params.count)
        for (key, value) in params {
            let safeKey = sanitizeToken(key)
            switch value {
            case .token(let s): out[safeKey] = sanitizeToken(s)
            case .count(let n): out[safeKey] = String(n)
            case .bucket(let b): out[safeKey] = sanitizeToken(b)
            case .flag(let b): out[safeKey] = b ? "true" : "false"
            }
        }
        return out
    }
}
