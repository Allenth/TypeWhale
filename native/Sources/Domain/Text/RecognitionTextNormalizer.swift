import Foundation

func cleanRecognitionText(_ text: String, languageMode: RecognitionLanguageMode = .load()) -> String {
    var cleaned = text
    let literalMarkers = [
        "**system**",
        "**user**",
        "**assistant**",
        "<system>",
        "</system>",
        "<user>",
        "</user>",
        "<assistant>",
        "</assistant>",
    ]
    for marker in literalMarkers {
        cleaned = cleaned.replacingOccurrences(of: marker, with: "", options: [.caseInsensitive])
    }
    cleaned = cleaned.replacingOccurrences(
        of: #"<\|[^|]{1,64}\|>"#,
        with: "",
        options: .regularExpression
    )
    cleaned = cleaned.replacingOccurrences(
        of: #"[ \t]{2,}"#,
        with: " ",
        options: .regularExpression
    )
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}
