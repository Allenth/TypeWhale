import Foundation

enum RemoteSystemEventIdentity: Hashable {
    case keyboard(keyCode: UInt16)
    case systemDefined(keyType: Int32)
}

enum RemoteSystemEventProfile {
    static func identities(for button: RemoteButton) -> [RemoteSystemEventIdentity] {
        switch button {
        case .power:
            return [.keyboard(keyCode: 90)]
        case .dpadUp:
            return [.keyboard(keyCode: 126)]
        case .dpadDown:
            return [.keyboard(keyCode: 125)]
        case .dpadLeft:
            return [.keyboard(keyCode: 123)]
        case .dpadRight:
            return [.keyboard(keyCode: 124)]
        case .center:
            return [.keyboard(keyCode: 36)]
        case .back:
            return []
        case .home:
            return [.keyboard(keyCode: 115)]
        case .menu:
            return [.keyboard(keyCode: 110)]
        case .volumeUp:
            return [.systemDefined(keyType: 0)]
        case .volumeDown:
            return [.systemDefined(keyType: 1)]
        case .tv:
            return [.keyboard(keyCode: 10), .keyboard(keyCode: 50)]
        case .voice:
            // Voice owns a longer hold-aware F5 correlation gate because it also gates ATVV.
            return []
        }
    }
}
