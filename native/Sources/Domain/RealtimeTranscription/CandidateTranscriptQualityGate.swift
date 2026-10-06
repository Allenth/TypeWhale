import Foundation

struct CandidateTranscriptQualityReport: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case accept
        case reject(Reason)
    }

    enum Reason: String, Equatable, Sendable {
        case notCompleted
        case empty
        case abnormalShortAgainstPreview
        case repeatedShortUnit
        case orphanLeadingFragment
        case punctuationStorm
    }

    let decision: Decision
    let normalizedCandidateText: String
}

struct CandidateTranscriptQualityGate: Sendable {
    func evaluate(
        candidate: CandidateDeliverySnapshot?,
        realtimePreviewFallbackText: String,
        languageMode: RecognitionLanguageMode
    ) -> CandidateTranscriptQualityReport {
        guard let candidate else {
            return CandidateTranscriptQualityReport(decision: .reject(.empty), normalizedCandidateText: "")
        }
        let normalizedCandidate = cleanRecognitionText(candidate.text, languageMode: languageMode)
        guard candidate.lifecycle == .completed else {
            return CandidateTranscriptQualityReport(
                decision: .reject(.notCompleted),
                normalizedCandidateText: normalizedCandidate
            )
        }
        guard isMeaningfulRecognitionText(normalizedCandidate) else {
            return CandidateTranscriptQualityReport(decision: .reject(.empty), normalizedCandidateText: "")
        }

        let candidateParts = CandidateTranscriptQualityParts(normalizedCandidate)
        let preview = cleanRecognitionText(realtimePreviewFallbackText, languageMode: languageMode)
        let previewParts = CandidateTranscriptQualityParts(preview)

        if candidateParts.hasRepeatedShortUnit {
            return CandidateTranscriptQualityReport(
                decision: .reject(.repeatedShortUnit),
                normalizedCandidateText: normalizedCandidate
            )
        }
        if candidateParts.hasPunctuationStorm {
            return CandidateTranscriptQualityReport(
                decision: .reject(.punctuationStorm),
                normalizedCandidateText: normalizedCandidate
            )
        }
        if hasOrphanLeadingFragment(candidate: candidateParts.semanticText, preview: previewParts.semanticText) {
            return CandidateTranscriptQualityReport(
                decision: .reject(.orphanLeadingFragment),
                normalizedCandidateText: normalizedCandidate
            )
        }
        if previewParts.cjkCount >= 12,
           candidateParts.cjkCount < Int(Double(previewParts.cjkCount) * 0.70),
           isCandidateClearlyShortFragment(candidate: candidateParts.semanticText, preview: previewParts.semanticText) {
            return CandidateTranscriptQualityReport(
                decision: .reject(.abnormalShortAgainstPreview),
                normalizedCandidateText: normalizedCandidate
            )
        }
        return CandidateTranscriptQualityReport(
            decision: .accept,
            normalizedCandidateText: normalizedCandidate
        )
    }

    private func hasOrphanLeadingFragment(candidate: String, preview: String) -> Bool {
        guard candidate.count >= 6, preview.count >= candidate.count else { return false }
        guard let first = candidate.first else { return false }
        let suspiciousLeadingCharacters: Set<Character> = ["案", "了", "呢", "吗", "啊", "嗯"]
        guard suspiciousLeadingCharacters.contains(first) else { return false }
        let remaining = String(candidate.dropFirst())
        guard remaining.count >= 5 else { return false }
        return preview.contains(remaining.prefix(5)) && !preview.hasPrefix(candidate)
    }

    private func isCandidateClearlyShortFragment(candidate: String, preview: String) -> Bool {
        guard candidate.count >= 2, preview.count > candidate.count else { return false }
        if preview.hasPrefix(candidate) || preview.hasSuffix(candidate) || preview.contains(candidate) {
            return true
        }
        let suffix = String(candidate.suffix(min(5, candidate.count)))
        return suffix.count >= 4 && preview.contains(suffix)
    }
}

private struct CandidateTranscriptQualityParts {
    let semanticText: String
    let cjkCount: Int
    let punctuationCount: Int

    init(_ text: String) {
        var semantic = ""
        var cjk = 0
        var punctuation = 0
        for scalar in text.unicodeScalars {
            if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                punctuation += 1
                continue
            }
            semantic.append(String(scalar))
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                cjk += 1
            }
        }
        semanticText = semantic
        cjkCount = cjk
        punctuationCount = punctuation
    }

    var hasPunctuationStorm: Bool {
        punctuationCount > max(2, semanticText.count / 2)
    }

    var hasRepeatedShortUnit: Bool {
        let allowedPairs: Set<String> = [
            "好好", "慢慢", "看看", "想想", "说说", "听听", "试试", "谢谢", "拜拜",
            "嗯嗯", "啊啊",
        ]
        let characters = Array(semanticText)
        guard characters.count >= 2 else { return false }
        for index in 1..<characters.count {
            guard characters[index] == characters[index - 1],
                  characters[index].isCJKUnifiedIdeograph else {
                continue
            }
            let pair = String([characters[index - 1], characters[index]])
            if !allowedPairs.contains(pair) {
                return true
            }
        }
        return false
    }
}

private extension Character {
    var isCJKUnifiedIdeograph: Bool {
        unicodeScalars.contains { scalar in
            scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }
    }
}
