import Foundation

func isMeaningfulRecognitionText(
    _ text: String,
    hasPriorPreview: Bool = false
) -> Bool {
    let compact = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    guard !compact.isEmpty else { return false }

    let semanticText = compact
        .unicodeScalars
        .filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
        .map(String.init)
        .joined()
    guard !semanticText.isEmpty else { return false }

    guard !hasPriorPreview else { return true }

    let likelySilenceHallucinations: Set<String> = [
        "我", "嗯", "啊", "呃", "额", "哦", "唔", "呣",
    ]
    if likelySilenceHallucinations.contains(semanticText) {
        return false
    }

    return true
}
