import AppKit
import Foundation

enum RecognitionLanguageMode: String, CaseIterable {
    case chinese

    static let defaultsKey = "recognitionLanguageMode"

    static func load() -> RecognitionLanguageMode {
        .chinese
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        }
    }

    var senseVoiceLanguage: String {
        switch self {
        case .chinese: return "auto"
        }
    }

    var segmentedIndex: Int {
        switch self {
        case .chinese: return 0
        }
    }

    static func fromSegmentedIndex(_ index: Int) -> RecognitionLanguageMode {
        .chinese
    }
}

struct ASRConfiguration {
    let languageMode: RecognitionLanguageMode

    static func current() -> ASRConfiguration {
        ASRConfiguration(languageMode: .load())
    }
}

struct RecordingTask {
    let id: UUID
    let audioURL: URL
    let targetApp: NSRunningApplication?
    let configuration: ASRConfiguration
    let duration: TimeInterval
    let finishRequestedAt: Date
}

struct RecentTranscription: Codable, Equatable {
    let text: String
    let recognitionSeconds: Double?
    let sourceText: String?
    let translatedText: String?
    let translationDirection: SmartTranslationDirection?
    let usage: SmartUsage?

    init(
        text: String,
        recognitionSeconds: Double?,
        sourceText: String? = nil,
        translatedText: String? = nil,
        translationDirection: SmartTranslationDirection? = nil,
        usage: SmartUsage? = nil
    ) {
        self.text = text
        self.recognitionSeconds = recognitionSeconds
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.translationDirection = translationDirection
        self.usage = usage
    }

    var hasTranslation: Bool {
        guard let sourceText, let translatedText else { return false }
        return !sourceText.isEmpty && !translatedText.isEmpty
    }

    var timeText: String {
        guard let recognitionSeconds else { return "识别时间 --" }
        return String(format: "识别时间 %.2f 秒", recognitionSeconds)
    }
}
