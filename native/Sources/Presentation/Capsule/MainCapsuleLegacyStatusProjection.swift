import Foundation

struct MainCapsuleLegacyStatusProjection: Equatable {
    let phase: MainCapsulePhase
    let statusTextOverride: String?

    init(statusText: String) {
        let normalized = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.statusTextOverride = normalized.isEmpty ? nil : normalized

        switch normalized {
        case "录音中":
            self.phase = .recording(instructions: nil)
        case "检测中":
            self.phase = .detectingSpeech
        case "识别中":
            self.phase = .recognizing
        case "整理中":
            self.phase = .rewriting
        case "翻译中":
            self.phase = .translating
        case "正在收尾":
            self.phase = .longFormFinishing(message: normalized)
        case "自动结束":
            self.phase = .autoFinished(message: normalized)
        case "无输入已停止":
            self.phase = .empty(reason: normalized)
        case "录音失败", "保存失败", "识别失败":
            self.phase = .failed(message: normalized)
        default:
            self.phase = .recording(instructions: nil)
        }
    }
}
