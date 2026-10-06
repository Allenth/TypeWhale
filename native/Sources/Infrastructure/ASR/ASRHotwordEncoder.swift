import Foundation

enum ASRHotwordPayload: Equatable {
    case none
    case list([String])
    case text(String)
    case context(String)
}

struct ASRProductionHotwordEncoding: Equatable {
    let payload: ASRHotwordPayload
    let skippedWords: [String]
}

enum ASRHotwordEncodingError: LocalizedError, Equatable {
    case invalidCharacters(String)
    case wordTooLong(String)
    case tooManyWords(Int)
    case phraseNotRepresentable(String)

    var errorDescription: String? {
        switch self {
        case .invalidCharacters(let word):
            return "热词包含目标模型不接受的换行或空字符：\(word)"
        case .wordTooLong(let word):
            return "热词超过 256 个字符：\(word)"
        case .tooManyWords(let count):
            return "单次测试最多使用 64 个热词，当前为 \(count) 个"
        case .phraseNotRepresentable(let word):
            return "目标模型使用空格分隔热词，无法无损表达包含空格的短语：\(word)"
        }
    }
}

enum ASRHotwordEncoder {
    static let maximumWordCount = 64
    static let maximumCharactersPerWord = 256

    static func encode(
        words: [String],
        strategy: ASRHotwordStrategy
    ) throws -> ASRHotwordPayload {
        guard strategy != .unsupported else { return .none }
        let normalized = try normalize(words)
        switch strategy {
        case .unsupported:
            return .none
        case .nativeList:
            return .list(normalized)
        case .nativeSpaceSeparated:
            if let phrase = normalized.first(where: { $0.rangeOfCharacter(from: .whitespacesAndNewlines) != nil }) {
                throw ASRHotwordEncodingError.phraseNotRepresentable(phrase)
            }
            return .text(normalized.joined(separator: " "))
        case .sherpaInline:
            return .text(normalized.joined(separator: " "))
        case .contextPrompt:
            return .context(normalized.joined(separator: ", "))
        }
    }

    static func encodeProduction(
        words: [String],
        strategy: ASRHotwordStrategy
    ) throws -> ASRProductionHotwordEncoding {
        guard strategy == .nativeSpaceSeparated else {
            return ASRProductionHotwordEncoding(
                payload: try encode(words: words, strategy: strategy),
                skippedWords: []
            )
        }
        let accepted = words.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }
        let skipped = words.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        }
        return ASRProductionHotwordEncoding(
            payload: try encode(words: accepted, strategy: strategy),
            skippedWords: skipped
        )
    }

    private static func normalize(_ words: [String]) throws -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for rawWord in words {
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if word.contains("\0") || word.contains("\n") || word.contains("\r") {
                throw ASRHotwordEncodingError.invalidCharacters(word)
            }
            if word.count > maximumCharactersPerWord {
                throw ASRHotwordEncodingError.wordTooLong(word)
            }
            if seen.insert(word).inserted {
                normalized.append(word)
            }
        }
        if normalized.count > maximumWordCount {
            throw ASRHotwordEncodingError.tooManyWords(normalized.count)
        }
        return normalized
    }
}
