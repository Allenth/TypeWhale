import Foundation

struct MainCapsuleState: Equatable {
    var phase: MainCapsulePhase
    var purpose: MainCapsulePurposeAppearance
    var context: MainCapsuleContext
    var indicators: MainCapsuleIndicators

    init(
        phase: MainCapsulePhase,
        purpose: MainCapsulePurposeAppearance = .dictation,
        context: MainCapsuleContext = .empty,
        indicators: MainCapsuleIndicators = .empty
    ) {
        self.phase = phase
        self.purpose = purpose
        self.context = context
        self.indicators = indicators
    }

    static func recording(
        instructions: String? = nil,
        purpose: MainCapsulePurposeAppearance = .dictation,
        context: MainCapsuleContext = .empty,
        indicators: MainCapsuleIndicators = .empty
    ) -> MainCapsuleState {
        MainCapsuleState(
            phase: .recording(instructions: instructions),
            purpose: purpose,
            context: context,
            indicators: indicators
        )
    }
}

enum MainCapsulePhase: Equatable {
    case idle
    case recording(instructions: String?)
    case detectingSpeech
    case recognizing
    case rewriting
    case translating
    case longFormFinishing(message: String)
    case completed
    case autoFinished(message: String)
    case empty(reason: String?)
    case failed(message: String)
    case hidden
}

enum MainCapsulePurposeAppearance: Equatable {
    case dictation
    case ideaPill
    case openClaw(connection: MainCapsuleOpenClawConnectionStatus)

    init(
        purpose: SpeechInputPurpose,
        openClawConnection: MainCapsuleOpenClawConnectionStatus = .checking
    ) {
        switch purpose {
        case .dictation:
            self = .dictation
        case .ideaPill:
            self = .ideaPill
        case .openClawChat:
            self = .openClaw(connection: openClawConnection)
        }
    }

    var modeName: String {
        switch self {
        case .dictation:
            return ""
        case .ideaPill:
            return "闪念胶囊"
        case .openClaw:
            return "OpenClaw"
        }
    }
}

enum MainCapsuleOpenClawConnectionStatus: Equatable {
    case checking
    case connected
    case unavailable
}

struct MainCapsuleContext: Equatable {
    var targetAppName: String?
    var modeName: String
    var autoTranslateEnabled: Bool

    init(
        targetAppName: String? = nil,
        modeName: String = "",
        autoTranslateEnabled: Bool = false
    ) {
        self.targetAppName = targetAppName
        self.modeName = modeName
        self.autoTranslateEnabled = autoTranslateEnabled
    }

    static let empty = MainCapsuleContext()
}

struct MainCapsuleIndicators: Equatable {
    var remainingSeconds: Int?
    var memoryHigh: Bool

    init(
        remainingSeconds: Int? = nil,
        memoryHigh: Bool = false
    ) {
        self.remainingSeconds = remainingSeconds
        self.memoryHigh = memoryHigh
    }

    static let empty = MainCapsuleIndicators()
}
