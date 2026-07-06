import Foundation

enum SpeechInputPurpose: Equatable {
    case dictation
    case ideaPill

    var capsuleModeName: String {
        switch self {
        case .dictation:
            return ""
        case .ideaPill:
            return "闪念胶囊"
        }
    }

    var shouldAutomaticallyPaste: Bool {
        switch self {
        case .dictation:
            return true
        case .ideaPill:
            return false
        }
    }
}
