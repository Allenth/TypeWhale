import Foundation

struct AppReopenPolicy {
    private var suppressedUntil: Date?

    mutating func suppress(until date: Date) {
        if let current = suppressedUntil, current > date {
            return
        }
        suppressedUntil = date
    }

    mutating func consumeSuppression(now: Date) -> Bool {
        guard let suppressedUntil else { return false }
        if now < suppressedUntil {
            self.suppressedUntil = nil
            return true
        }
        self.suppressedUntil = nil
        return false
    }
}
