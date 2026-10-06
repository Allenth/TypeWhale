import Foundation

enum RemoteButton: String, CaseIterable, Codable, Hashable {
    case voice
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case center
    case back
    case home
    case menu
    case volumeUp
    case volumeDown
    case tv
    case power
}
