import Foundation

struct LongFormDiskSafetyProbeGate {
    private let minimumInterval: TimeInterval
    private var lastStartedAt: Date?
    private var isInFlight = false

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    mutating func beginIfDue(at now: Date) -> Bool {
        guard !isInFlight else { return false }
        if let lastStartedAt,
           now.timeIntervalSince(lastStartedAt) < minimumInterval {
            return false
        }
        lastStartedAt = now
        isInFlight = true
        return true
    }

    mutating func complete() {
        isInFlight = false
    }

    mutating func reset() {
        lastStartedAt = nil
        isInFlight = false
    }
}
