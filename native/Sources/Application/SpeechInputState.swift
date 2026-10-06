import AppKit
import Foundation

enum RecordingActivation {
    case toggle
    case hold
}

enum SpeechCaptureSource: Equatable {
    case microphone
    case remote(sampleRate: Int)

    var requiresMicrophonePermission: Bool {
        if case .microphone = self { return true }
        return false
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}

struct SpeechSession {
    let id: UUID
    let channel: SpeechInputChannel
    var targetApp: NSRunningApplication?
    let configuration: ASRConfiguration
    let activation: RecordingActivation
    let captureSource: SpeechCaptureSource
    let purpose: SpeechInputPurpose
    let realtimeEnabled: Bool
    let experimentalPreviewSettings: ExperimentalPreviewSettings
    /// 本次录音开始时冻结的收尾策略；录音中途修改设置只影响下一次录音。
    let reRecognizeWholeRecordingAfterStop: Bool
    /// 已提交（冻结）的实时预览前缀：滚出当前块的文本，不再重识别、永不跳变。
    var committedPreviewText: String = ""
    /// 当前块的实时识别尾巴（会随重识别更新）；显示 = committedPreviewText + latestPreviewText。
    var latestPreviewText: String
    /// 当前正在识别的块序号；用于丢弃已提交块的滞后快照。
    var currentChunkIndex: Int = 0

    func matchesTrigger(channel: SpeechInputChannel, purpose: SpeechInputPurpose) -> Bool {
        self.channel == channel && self.purpose == purpose
    }
}

struct RealtimeSnapshotRequest {
    let taskID: UUID
    let samples: [Float]
    let sampleRate: Int
    let configuration: ASRConfiguration
    let chunkIndex: Int
    let isChunkFinal: Bool
    let audioDuration: TimeInterval
    /// 当前块快照在整段录音中的绝对音频范围。
    let audioRange: PreviewAudioRange
    /// 该快照被录音器交给实时识别时，已覆盖到本次录音的大致时间点。
    /// 用于停止后判断实时缓存是否覆盖到录音末尾，避免尾巴没进缓存却被直接粘贴。
    let audioCoverageSeconds: TimeInterval
}

struct PendingPasteResult {
    let task: RecordingTask
    let text: String
    let rawText: String
    let sourceText: String?
    let translatedText: String?
    let translationDirection: SmartTranslationDirection?
    let wasTranslationRequested: Bool
    let rewriteMode: RewriteMode?
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
