import Foundation

enum PasteOutcome {
    case directInserted(Date)
    case restored(Date)
    case preservedUserClipboard(Date)
    case failed(String)

    var pasteCompletedAt: Date? {
        switch self {
        case .directInserted(let date), .restored(let date), .preservedUserClipboard(let date):
            return date
        case .failed:
            return nil
        }
    }
}
