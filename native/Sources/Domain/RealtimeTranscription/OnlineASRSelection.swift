import Foundation

enum OnlineASRProviderSelection: String, CaseIterable, Equatable, Sendable {
    case off
    case doubao
    case mimoV25

    var displayName: String {
        switch self {
        case .off: "关闭"
        case .doubao: "豆包 ASR"
        case .mimoV25: "MiMo‑V2.5-ASR"
        }
    }
}
