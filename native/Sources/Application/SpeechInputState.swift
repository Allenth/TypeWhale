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
    /// 已提交（冻结）的实时预览前缀：滚出当前块的文本，不再重识别、永不跳变。
    var committedPreviewText: String = ""
    /// 当前块的实时识别尾巴（会随重识别更新）；显示 = committedPreviewText + latestPreviewText。
    var latestPreviewText: String
    /// 当前正在识别的块序号；用于丢弃已提交块的滞后快照。
    var currentChunkIndex: Int = 0
}

struct RealtimeSnapshotRequest {
    let taskID: UUID
    let audioURL: URL
    let configuration: ASRConfiguration
    let chunkIndex: Int
    let isChunkFinal: Bool
    /// 该块是否达到过近场响度；未达到则视为远场/弱信号，预览不接受其文本。
    let reachedNearField: Bool
}

struct PendingPasteResult {
    let task: RecordingTask
    let text: String
    let rawText: String
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

    var logName: String {
        switch self {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .finalizing:
            return "finalizing"
        case .pasting:
            return "pasting"
        case .failed:
            return "failed"
        }
    }
}
