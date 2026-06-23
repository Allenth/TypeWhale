import Foundation

final class DeveloperTermNormalizer {
    private let termsProvider: () -> [DeveloperTerm]

    init(termsProvider: @escaping () -> [DeveloperTerm] = { DeveloperLexiconStore.load() }) {
        self.termsProvider = termsProvider
    }

    func normalize(_ rawText: String, context: SmartInputContext) -> DeveloperTermNormalizationResult {
        guard !context.isSecureTextEntry else {
            return DeveloperTermNormalizationResult(text: rawText, replacements: [])
        }
        let terms = termsProvider()
        guard !terms.isEmpty, !rawText.isEmpty else {
            return DeveloperTermNormalizationResult(text: rawText, replacements: [])
        }

        var text = rawText
        var replacements: [DeveloperTermReplacement] = []
        let aliases = buildAliases(from: terms)

        for item in aliases {
            let matches = findMatches(alias: item.alias, in: text, caseSensitive: item.caseSensitive)
            guard !matches.isEmpty else { continue }
            for range in matches.reversed() {
                let original = String(text[range])
                guard original != item.canonical else { continue }
                text.replaceSubrange(range, with: replacementText(item.canonical, in: text, range: range))
                replacements.append(DeveloperTermReplacement(original: original, canonical: item.canonical))
            }
        }

        return DeveloperTermNormalizationResult(text: text, replacements: replacements.reversed())
    }

    private struct AliasItem {
        let alias: String
        let canonical: String
        let caseSensitive: Bool
    }

    private func buildAliases(from terms: [DeveloperTerm]) -> [AliasItem] {
        terms.flatMap { term in
            ([term.canonical] + term.aliases).compactMap { alias in
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else { return nil }
                guard !isUnsafeAlias(trimmed, canonical: term.canonical) else { return nil }
                return AliasItem(alias: trimmed, canonical: term.canonical, caseSensitive: term.caseSensitive)
            }
        }
        .sorted {
            normalizedLength($0.alias) == normalizedLength($1.alias)
                ? $0.alias.count > $1.alias.count
                : normalizedLength($0.alias) > normalizedLength($1.alias)
        }
    }

    private func isUnsafeAlias(_ alias: String, canonical: String) -> Bool {
        let lower = alias.lowercased()
        if lower == "code" && canonical != "code" { return true }
        if lower.count <= 2 && !["ui", "ux"].contains(lower) { return true }
        return false
    }

    private func normalizedLength(_ value: String) -> Int {
        value.filter { !$0.isWhitespace && !$0.isPunctuation }.count
    }

    private func findMatches(alias: String, in text: String, caseSensitive: Bool) -> [Range<String.Index>] {
        if containsWhitespaceOrPunctuation(alias) {
            return findLooseMatches(alias: alias, in: text, caseSensitive: caseSensitive)
        }
        return findExactMatches(alias: alias, in: text, caseSensitive: caseSensitive)
    }

    private func findExactMatches(alias: String, in text: String, caseSensitive: Bool) -> [Range<String.Index>] {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: alias, options: options, range: searchStart..<text.endIndex) {
            if hasSafeBoundaries(range, in: text) {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }
        return ranges
    }

    private func findLooseMatches(alias: String, in text: String, caseSensitive: Bool) -> [Range<String.Index>] {
        let target = comparable(alias, caseSensitive: caseSensitive)
        guard !target.isEmpty else { return [] }
        let characters = Array(text.indices)
        var ranges: [Range<String.Index>] = []
        var startOffset = 0
        while startOffset < characters.count {
            var normalized = ""
            var endOffset = startOffset
            while endOffset < characters.count && normalized.count <= target.count + 4 {
                let index = characters[endOffset]
                let scalar = text[index]
                if scalar.isLetter || scalar.isNumber || isChinese(scalar) {
                    normalized.append(contentsOf: comparable(String(scalar), caseSensitive: caseSensitive))
                }
                if normalized == target {
                    let lower = characters[startOffset]
                    let upper = text.index(after: characters[endOffset])
                    let range = lower..<upper
                    if hasSafeBoundaries(range, in: text) {
                        ranges.append(range)
                    }
                    startOffset = endOffset
                    break
                }
                if !target.hasPrefix(normalized) && !normalized.isEmpty {
                    break
                }
                endOffset += 1
            }
            startOffset += 1
        }
        return ranges
    }

    private func comparable(_ value: String, caseSensitive: Bool) -> String {
        let filtered = value.filter { $0.isLetter || $0.isNumber || isChinese($0) }
        return caseSensitive ? filtered : filtered.lowercased()
    }

    private func containsWhitespaceOrPunctuation(_ value: String) -> Bool {
        value.contains { $0.isWhitespace || $0.isPunctuation }
    }

    private func hasSafeBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return !isLatinOrNumber(before) && !isLatinOrNumber(after)
    }

    private func replacementText(_ canonical: String, in text: String, range: Range<String.Index>) -> String {
        var value = canonical
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        if canonical.contains(where: { $0.isLetter }) {
            if let before, isChinese(before), !value.hasPrefix(" ") {
                value = " " + value
            }
            if let after, isChinese(after), !value.hasSuffix(" ") {
                value += " "
            }
        }
        return value
    }

    private func isLatinOrNumber(_ character: Character?) -> Bool {
        guard let character else { return false }
        let isASCII = character.unicodeScalars.allSatisfy { $0.isASCII }
        return isASCII && (character.isLetter || character.isNumber)
    }

    private func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }
}
