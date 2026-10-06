import Foundation

enum SpeechInputPurpose: Equatable {
    case dictation
    case ideaPill
    case openClawChat

    var logName: String {
        switch self {
        case .dictation:
            return "dictation"
        case .ideaPill:
            return "ideaPill"
        case .openClawChat:
            return "openClawChat"
        }
    }

    var capsuleModeName: String {
        switch self {
        case .dictation:
            return ""
        case .ideaPill:
            return "闪念胶囊"
        case .openClawChat:
            return "OpenClaw"
        }
    }

    var shouldAutomaticallyPaste: Bool {
        switch self {
        case .dictation:
            return true
        case .ideaPill, .openClawChat:
            return false
        }
    }
}
