import Foundation

struct HotkeyEventTiming: Equatable {
    let eventUptimeNanoseconds: UInt64
    let observedUptimeNanoseconds: UInt64

    var deliveryLagMilliseconds: UInt64? {
        guard eventUptimeNanoseconds > 0,
              observedUptimeNanoseconds >= eventUptimeNanoseconds else { return nil }
        let lag = observedUptimeNanoseconds - eventUptimeNanoseconds
        guard lag <= 60_000_000_000 else { return nil }
        return lag / 1_000_000
    }
}

struct HotkeyPressGesturePolicy {
    enum ReleaseDecision: Equatable {
        case shortPress(durationMilliseconds: UInt64)
        case longPress(durationMilliseconds: UInt64, holdActivated: Bool)
        case unmatched

        var durationMilliseconds: UInt64? {
            switch self {
            case .shortPress(let durationMilliseconds),
                 .longPress(let durationMilliseconds, _):
                return durationMilliseconds
            case .unmatched:
                return nil
            }
        }

        var logName: String {
            switch self {
            case .shortPress: return "short"
            case .longPress(_, let holdActivated):
                return holdActivated ? "long_activated" : "long_delayed"
            case .unmatched: return "unmatched"
            }
        }
    }

    private struct ActivePress {
        let id: UInt64
        let beganAt: HotkeyEventTiming
        var holdActivated: Bool
    }

    let longPressThresholdNanoseconds: UInt64
    private var nextPressID: UInt64 = 1
    private var activePress: ActivePress?

    init(longPressThresholdNanoseconds: UInt64) {
        self.longPressThresholdNanoseconds = longPressThresholdNanoseconds
    }

    mutating func begin(at timing: HotkeyEventTiming) -> UInt64 {
        if let activePress { return activePress.id }
        let pressID = nextPressID
        nextPressID &+= 1
        if nextPressID == 0 { nextPressID = 1 }
        activePress = ActivePress(id: pressID, beganAt: timing, holdActivated: false)
        return pressID
    }

    mutating func markHoldActivated(pressID: UInt64) -> Bool {
        guard var press = activePress,
              press.id == pressID,
              !press.holdActivated else { return false }
        press.holdActivated = true
        activePress = press
        return true
    }

    mutating func release(at timing: HotkeyEventTiming) -> ReleaseDecision {
        guard let press = activePress else { return .unmatched }
        activePress = nil
        let duration = durationNanoseconds(from: press.beganAt, to: timing)
        let milliseconds = duration / 1_000_000
        if press.holdActivated || duration >= longPressThresholdNanoseconds {
            return .longPress(
                durationMilliseconds: milliseconds,
                holdActivated: press.holdActivated
            )
        }
        return .shortPress(durationMilliseconds: milliseconds)
    }

    mutating func reset() {
        activePress = nil
    }

    private func durationNanoseconds(
        from down: HotkeyEventTiming,
        to up: HotkeyEventTiming
    ) -> UInt64 {
        if down.eventUptimeNanoseconds > 0,
           up.eventUptimeNanoseconds > down.eventUptimeNanoseconds {
            return up.eventUptimeNanoseconds - down.eventUptimeNanoseconds
        }
        guard up.observedUptimeNanoseconds >= down.observedUptimeNanoseconds else { return 0 }
        return up.observedUptimeNanoseconds - down.observedUptimeNanoseconds
    }
}
