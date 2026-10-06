import Foundation

enum MainCapsuleRenderStatus: Equatable {
    case idle
    case recording
    case content
    case processing
    case empty
    case failure
    case hidden
}

enum MainCapsulePurposeGlow: Equatable {
    case ideaPill
    case openClaw
}

struct MainCapsuleRenderState: Equatable {
    let status: MainCapsuleRenderStatus
    let statusText: String
    let purpose: MainCapsulePurposeAppearance
    let context: MainCapsuleContext
    let indicators: MainCapsuleIndicators
    let targetText: String
    let visibleCharacterCount: Int
    let visibleStableCharacterCount: Int
    let needsTextTimer: Bool
    let waveformBands: [Float]

    var openClawConnectionStatus: MainCapsuleOpenClawConnectionStatus? {
        guard case let .openClaw(connection) = purpose else { return nil }
        return connection
    }

    var purposeGlow: MainCapsulePurposeGlow? {
        switch purpose {
        case .dictation:
            return nil
        case .ideaPill:
            return .ideaPill
        case .openClaw:
            return .openClaw
        }
    }

    init(
        state: MainCapsuleState,
        contentText: String,
        motion: MainCapsuleTextMotion,
        waveform: MainCapsuleWaveformMotion = MainCapsuleWaveformMotion(),
        statusTextOverride: String? = nil
    ) {
        self.status = MainCapsuleRenderState.status(for: state.phase, contentText: contentText)
        self.statusText = statusTextOverride?.isEmpty == false
            ? statusTextOverride!
            : MainCapsuleRenderState.statusText(for: state.phase)
        self.purpose = state.purpose
        self.context = state.context
        self.indicators = state.indicators
        self.targetText = contentText

        let contentCount = max(0, contentText.count)
        self.visibleCharacterCount = min(max(0, motion.visibleCharacterCount), contentCount)
        self.visibleStableCharacterCount = min(max(0, motion.visibleStableCharacterCount), self.visibleCharacterCount)
        self.needsTextTimer = motion.needsTimer && self.visibleCharacterCount < contentCount
        self.waveformBands = waveform.bands
    }

    var displayedText: String {
        String(targetText.prefix(visibleCharacterCount))
    }

    var isHidden: Bool {
        status == .hidden
    }

    private static func status(
        for phase: MainCapsulePhase,
        contentText: String
    ) -> MainCapsuleRenderStatus {
        switch phase {
        case .idle:
            return .idle
        case .recording:
            return .recording
        case .detectingSpeech,
             .recognizing,
             .rewriting,
             .translating,
             .longFormFinishing,
             .completed,
             .autoFinished:
            return .processing
        case .empty:
            return .empty
        case .failed:
            return .failure
        case .hidden:
            return .hidden
        }
    }

    private static func statusText(for phase: MainCapsulePhase) -> String {
        switch phase {
        case .idle:
            return ""
        case .recording:
            return "录音中"
        case .detectingSpeech:
            return "检测中"
        case .recognizing:
            return "识别中"
        case .rewriting:
            return "整理中"
        case .translating:
            return "翻译中"
        case .longFormFinishing:
            return "正在收尾"
        case .completed:
            return "识别完成"
        case .autoFinished:
            return "自动结束"
        case .empty:
            return "无输入已停止"
        case .failed(let message):
            return message
        case .hidden:
            return ""
        }
    }
}
