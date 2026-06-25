import Foundation

func isMeaningfulRecognitionText(
    _ text: String,
    hasPriorPreview: Bool = false
) -> Bool {
    meaningfulRecognitionTextParts(text).isMeaningful(hasPriorPreview: hasPriorPreview)
}

func isMeaningfulRealtimePreviewText(
    _ text: String,
    previousPreview: String
) -> Bool {
    let parts = meaningfulRecognitionTextParts(text)
    guard parts.isMeaningful(hasPriorPreview: !previousPreview.isEmpty) else { return false }

    let previousParts = meaningfulRecognitionTextParts(previousPreview)
    guard parts.semanticText != previousParts.semanticText else { return false }

    if parts.semanticText.count <= 1 {
        return false
    }

    if !previousParts.semanticText.isEmpty,
       parts.semanticText.count <= previousParts.semanticText.count,
       previousParts.semanticText.hasPrefix(parts.semanticText) {
        return false
    }

    if !previousParts.semanticText.isEmpty,
       parts.semanticText.count < previousParts.semanticText.count,
       previousParts.semanticText.contains(parts.semanticText) {
        return false
    }

    if parts.punctuationCount >= 2,
       parts.semanticText.count <= 2 {
        return false
    }

    if parts.punctuationCount > max(2, parts.semanticText.count) {
        return false
    }

    if parts.hasSuspiciousShortLatinNoise {
        return false
    }

    return true
}

private struct RecognitionTextParts {
    let compact: String
    let semanticText: String
    let punctuationCount: Int
    let shortLatinRunCount: Int
    let containsCJK: Bool

    var hasSuspiciousShortLatinNoise: Bool {
        containsCJK && shortLatinRunCount > 0 && punctuationCount >= 2
    }

    func isMeaningful(hasPriorPreview: Bool) -> Bool {
        guard !compact.isEmpty, !semanticText.isEmpty else { return false }
        guard !hasPriorPreview else { return true }

        let likelySilenceHallucinations: Set<String> = [
            "我", "嗯", "啊", "呃", "额", "哦", "唔", "呣",
        ]
        if likelySilenceHallucinations.contains(semanticText) {
            return false
        }

        return true
    }
}

private func meaningfulRecognitionTextParts(_ text: String) -> RecognitionTextParts {
    let compact = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    var semanticScalars: [String] = []
    var punctuationCount = 0
    var shortLatinRunCount = 0
    var currentLatinRunLength = 0
    var containsCJK = false
    func finishLatinRun() {
        if (1...2).contains(currentLatinRunLength) {
            shortLatinRunCount += 1
        }
        currentLatinRunLength = 0
    }
    for scalar in compact.unicodeScalars {
        if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
            finishLatinRun()
            punctuationCount += 1
        } else {
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                containsCJK = true
                finishLatinRun()
            } else if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
                currentLatinRunLength += 1
            } else {
                finishLatinRun()
            }
            semanticScalars.append(String(scalar))
        }
    }
    finishLatinRun()
    return RecognitionTextParts(
        compact: compact,
        semanticText: semanticScalars.joined(),
        punctuationCount: punctuationCount,
        shortLatinRunCount: shortLatinRunCount,
        containsCJK: containsCJK
    )
}
