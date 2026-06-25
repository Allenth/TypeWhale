import AppKit
import Foundation

enum RecordingActivation {
    case toggle
    case hold
}

struct SpeechSession {
    let id: UUID
    var targetApp: NSRunningApplication?
    let configuration: ASRConfiguration
    let activation: RecordingActivation
    let realtimeEnabled: Bool
    /// 当前在说的这一段（自上次静音/提交以来）的实时识别结果。
    var latestPreviewText: String
    /// 已说完并冻结的前缀：分段提交后累积，不再被滑动窗口重识别覆盖。
    var committedPreviewText: String = ""
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
