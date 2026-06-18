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
}

struct RecentTranscription: Codable, Equatable {
    let text: String
    let recognitionSeconds: Double?

    var timeText: String {
        guard let recognitionSeconds else { return "识别时间 --" }
        return String(format: "识别时间 %.2f 秒", recognitionSeconds)
    }
}
