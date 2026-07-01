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

        applyFuzzyMatches(aliases: aliases, to: &text, replacements: &replacements)

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
        let comparableAlias: String
        let comparableCanonical: String
        let allowsFuzzy: Bool
    }

    private struct FuzzyToken {
        let range: Range<String.Index>
        let group: Int
    }

    private struct FuzzyMatch {
        let range: Range<String.Index>
        let item: AliasItem
        let distance: Int
    }

    private func buildAliases(from terms: [DeveloperTerm]) -> [AliasItem] {
        terms.flatMap { term in
            ([term.canonical] + term.aliases).compactMap { alias in
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else { return nil }
                guard !isUnsafeAlias(trimmed, canonical: term.canonical) else { return nil }
                return AliasItem(
                    alias: trimmed,
                    canonical: term.canonical,
                    caseSensitive: term.caseSensitive,
                    comparableAlias: comparable(trimmed, caseSensitive: term.caseSensitive),
                    comparableCanonical: comparable(term.canonical, caseSensitive: term.caseSensitive),
                    allowsFuzzy: term.allowsFuzzy && allowsFuzzyInference(for: trimmed)
                )
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
        if lower.count <= 2 && !["ui", "ux"].contains(lower) && !alias.contains(where: isChinese) { return true }
        return false
    }

    private func allowsFuzzyInference(for alias: String) -> Bool {
        guard alias.allSatisfy({ character in
            character.unicodeScalars.allSatisfy { $0.isASCII }
        }) else { return false }
        let comparableAlias = comparable(alias, caseSensitive: false)
        guard comparableAlias.count >= 5 else { return false }
        return comparableAlias.contains { $0.isLetter }
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

    private func applyFuzzyMatches(
        aliases: [AliasItem],
        to text: inout String,
        replacements: inout [DeveloperTermReplacement]
    ) {
        let fuzzyAliases = aliases.filter(\.allowsFuzzy)
        guard !fuzzyAliases.isEmpty else { return }

        var safetyCounter = 0
        while safetyCounter < 32, let match = bestFuzzyMatch(in: text, aliases: fuzzyAliases) {
            let original = String(text[match.range])
            guard original != match.item.canonical else { break }
            text.replaceSubrange(match.range, with: replacementText(match.item.canonical, in: text, range: match.range))
            replacements.append(DeveloperTermReplacement(original: original, canonical: match.item.canonical))
            safetyCounter += 1
        }
    }

    private func bestFuzzyMatch(in text: String, aliases: [AliasItem]) -> FuzzyMatch? {
        let tokens = fuzzyTokens(in: text)
        guard !tokens.isEmpty else { return nil }

        var best: FuzzyMatch?
        for startIndex in tokens.indices {
            var endIndex = startIndex
            while endIndex < tokens.count,
                  tokens[endIndex].group == tokens[startIndex].group,
                  endIndex - startIndex < 4 {
                let range = tokens[startIndex].range.lowerBound..<tokens[endIndex].range.upperBound
                if hasSafeFuzzyBoundaries(range, in: text),
                   let match = bestFuzzyAlias(for: String(text[range]), range: range, aliases: aliases),
                   isBetterFuzzyMatch(match, than: best) {
                    best = match
                }
                endIndex += 1
            }
        }
        return best
    }

    private func bestFuzzyAlias(
        for segment: String,
        range: Range<String.Index>,
        aliases: [AliasItem]
    ) -> FuzzyMatch? {
        let segmentComparable = comparable(segment, caseSensitive: false)
        guard segmentComparable.count >= 5 else { return nil }
        guard !aliases.contains(where: { item in
            item.comparableAlias.lowercased() == segmentComparable ||
                item.comparableCanonical.lowercased() == segmentComparable
        }) else {
            return nil
        }

        var best: FuzzyMatch?
        for item in aliases {
            let compareOptions: String.CompareOptions = item.caseSensitive ? [] : [.caseInsensitive]
            guard segment.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(item.canonical, options: compareOptions) != .orderedSame else {
                continue
            }
            let target = item.comparableAlias.lowercased()
            guard target != segmentComparable else { continue }
            guard item.comparableCanonical.lowercased() != segmentComparable else { continue }
            let limit = fuzzyDistanceLimit(for: target.count)
            guard abs(segmentComparable.count - target.count) <= limit else { continue }
            guard hasCompatibleFuzzyPrefix(segmentComparable, target) else { continue }
            let distance = editDistance(segmentComparable, target, maxDistance: limit)
            guard distance <= limit else { continue }

            let match = FuzzyMatch(range: range, item: item, distance: distance)
            if isBetterFuzzyMatch(match, than: best) {
                best = match
            }
        }
        return best
    }

    private func isBetterFuzzyMatch(_ candidate: FuzzyMatch, than current: FuzzyMatch?) -> Bool {
        guard let current else { return true }
        if candidate.distance != current.distance {
            return candidate.distance < current.distance
        }
        if candidate.item.comparableAlias.count != current.item.comparableAlias.count {
            return candidate.item.comparableAlias.count > current.item.comparableAlias.count
        }
        return candidate.item.alias.count > current.item.alias.count
    }

    private func fuzzyTokens(in text: String) -> [FuzzyToken] {
        var tokens: [FuzzyToken] = []
        var group = 0
        var tokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if isFuzzyContentCharacter(character) {
                if tokenStart == nil {
                    tokenStart = index
                }
            } else {
                if let start = tokenStart {
                    tokens.append(FuzzyToken(range: start..<index, group: group))
                    tokenStart = nil
                }
                if !isFuzzySeparator(character) {
                    group += 1
                }
            }
            index = text.index(after: index)
        }

        if let tokenStart {
            tokens.append(FuzzyToken(range: tokenStart..<text.endIndex, group: group))
        }
        return tokens
    }

    private func isFuzzyContentCharacter(_ character: Character) -> Bool {
        let isASCII = character.unicodeScalars.allSatisfy { $0.isASCII }
        return isASCII && (character.isLetter || character.isNumber)
    }

    private func isFuzzySeparator(_ character: Character) -> Bool {
        guard character.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        return character.isWhitespace || [".", "-", "_"].contains(character)
    }

    private func hasSafeFuzzyBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        guard hasSafeBoundaries(range, in: text) else { return false }
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return !isTightFuzzySeparator(before) && !isTightFuzzySeparator(after)
    }

    private func isTightFuzzySeparator(_ character: Character?) -> Bool {
        guard let character else { return false }
        return [".", "-", "_"].contains(character)
    }

    private func fuzzyDistanceLimit(for targetLength: Int) -> Int {
        if targetLength <= 7 { return 1 }
        if targetLength <= 12 { return 2 }
        return 3
    }

    private func hasCompatibleFuzzyPrefix(_ lhs: String, _ rhs: String) -> Bool {
        let lhsValues = Array(lhs)
        let rhsValues = Array(rhs)
        guard let lhsFirst = lhsValues.first, let rhsFirst = rhsValues.first, lhsFirst == rhsFirst else {
            return false
        }
        guard min(lhsValues.count, rhsValues.count) >= 8 else { return true }
        return lhsValues.dropFirst().first == rhsValues.dropFirst().first
    }

    private func editDistance(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int {
        let lhsValues = Array(lhs)
        let rhsValues = Array(rhs)
        if lhsValues.isEmpty { return rhsValues.count }
        if rhsValues.isEmpty { return lhsValues.count }

        var previous = Array(0...rhsValues.count)
        for lhsIndex in 1...lhsValues.count {
            var current = [lhsIndex] + Array(repeating: 0, count: rhsValues.count)
            var rowMinimum = current[0]
            for rhsIndex in 1...rhsValues.count {
                let substitutionCost = lhsValues[lhsIndex - 1] == rhsValues[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rhsIndex])
            }
            if rowMinimum > maxDistance {
                return maxDistance + 1
            }
            previous = current
        }
        return previous[rhsValues.count]
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
