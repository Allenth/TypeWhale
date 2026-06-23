import AppKit
import Foundation

enum RecordingActivation {
    case toggle
    case hold
}

struct SpeechSession {
    let id: UUID
    let targetApp: NSRunningApplication?
    let configuration: ASRConfiguration
    let activation: RecordingActivation
    let realtimeEnabled: Bool
    var latestPreviewText: String
}

struct RealtimeSnapshotRequest {
    let taskID: UUID
    let audioURL: URL
    let configuration: ASRConfiguration
}

struct PendingPasteResult {
    let task: RecordingTask
    let text: String
    let sourceText: String?
    let translatedText: String?
    let translationDirection: SmartTranslationDirection?
    let usage: SmartUsage?
}

enum SpeechInputState {
    case idle
    case recording(UUID)
    case finalizing(RecordingTask)
    case pasting(RecordingTask)
    case failed(String)
}
