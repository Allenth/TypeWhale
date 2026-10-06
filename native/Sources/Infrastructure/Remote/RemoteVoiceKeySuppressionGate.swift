import Foundation

private enum RemoteVoiceKeySuppressionTiming {
    static let maximumSupportedHoldNanoseconds: UInt64 = 310_000_000_000
}

enum RemoteVoiceKeySuppressionDecision: Equatable {
    case consumeRemoteVoiceDown(correlationMilliseconds: UInt64)
    case consumeRemoteVoiceRepeat
    case consumeRemoteVoiceUp(correlationMilliseconds: UInt64?)
    case pass

    var shouldConsume: Bool {
        self != .pass
    }

    var logName: String {
        switch self {
        case .consumeRemoteVoiceDown: return "consume_down"
        case .consumeRemoteVoiceRepeat: return "consume_repeat"
        case .consumeRemoteVoiceUp: return "consume_up"
        case .pass: return "pass"
        }
    }
}

/// Correlates RC003's low-level voice usage with the F5 CGEvent generated from the same HID report.
/// It intentionally does not seize the remote and never suppresses an uncorrelated physical F5.
struct RemoteVoiceKeySuppressionGate {
    static let f5VirtualKeyCode = 96

    private struct Cycle {
        let downEventTimestamp: UInt64
        let downObservedAt: UInt64
        var downConsumedAt: UInt64?
        var upEventTimestamp: UInt64?
        var upObservedAt: UInt64?
    }

    let correlationWindowNanoseconds: UInt64
    let maximumHeldNanoseconds: UInt64
    private var cycle: Cycle?

    init(
        correlationWindowNanoseconds: UInt64 = 120_000_000,
        maximumHeldNanoseconds: UInt64 = RemoteVoiceKeySuppressionTiming.maximumSupportedHoldNanoseconds
    ) {
        self.correlationWindowNanoseconds = correlationWindowNanoseconds
        self.maximumHeldNanoseconds = maximumHeldNanoseconds
    }

    mutating func observeRemoteVoiceHID(
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) {
        expireIfNeeded(observedAt: observedAt)
        if isDown {
            guard cycle == nil else { return }
            cycle = Cycle(
                downEventTimestamp: eventTimestamp,
                downObservedAt: observedAt,
                downConsumedAt: nil,
                upEventTimestamp: nil,
                upObservedAt: nil
            )
            return
        }
        guard var active = cycle else { return }
        active.upEventTimestamp = eventTimestamp
        active.upObservedAt = observedAt
        cycle = active
    }

    mutating func decide(
        keyCode: Int,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) -> RemoteVoiceKeySuppressionDecision {
        expireIfNeeded(observedAt: observedAt)
        guard keyCode == Self.f5VirtualKeyCode, var active = cycle else { return .pass }

        if isDown {
            if active.downConsumedAt != nil {
                return .consumeRemoteVoiceRepeat
            }
            guard let delta = correlationDelta(
                    eventTimestamp,
                    active.downEventTimestamp,
                    observedAt,
                    active.downObservedAt
                  ) else { return .pass }
            active.downConsumedAt = observedAt
            cycle = active
            return .consumeRemoteVoiceDown(correlationMilliseconds: delta / 1_000_000)
        }

        guard active.downConsumedAt != nil else { return .pass }
        let delta: UInt64?
        if let hidUpTimestamp = active.upEventTimestamp,
           let hidUpObservedAt = active.upObservedAt {
            delta = correlationDelta(
                eventTimestamp,
                hidUpTimestamp,
                observedAt,
                hidUpObservedAt
            ).map { $0 / 1_000_000 }
        } else {
            delta = nil
        }
        cycle = nil
        return .consumeRemoteVoiceUp(correlationMilliseconds: delta)
    }

    mutating func reset() {
        cycle = nil
    }

    private mutating func expireIfNeeded(observedAt: UInt64) {
        guard let active = cycle else { return }
        let reference: UInt64
        let lifetime: UInt64
        if let upObservedAt = active.upObservedAt {
            reference = upObservedAt
            lifetime = correlationWindowNanoseconds
        } else if let downConsumedAt = active.downConsumedAt {
            reference = downConsumedAt
            lifetime = maximumHeldNanoseconds
        } else {
            reference = active.downObservedAt
            lifetime = correlationWindowNanoseconds
        }
        guard observedAt >= reference,
              observedAt - reference > lifetime else { return }
        cycle = nil
    }

    private func correlationDelta(
        _ cgTimestamp: UInt64,
        _ hidTimestamp: UInt64,
        _ cgObservedAt: UInt64,
        _ hidObservedAt: UInt64
    ) -> UInt64? {
        let eventDelta = absoluteDifference(cgTimestamp, hidTimestamp)
        guard eventDelta <= correlationWindowNanoseconds else { return nil }
        let observationDelta = absoluteDifference(cgObservedAt, hidObservedAt)
        guard observationDelta <= correlationWindowNanoseconds else { return nil }
        return eventDelta
    }

    private func absoluteDifference(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}

final class RemoteVoiceKeySuppressionRegistry {
    static let shared = RemoteVoiceKeySuppressionRegistry()

    private let lock = NSLock()
    private var gate = RemoteVoiceKeySuppressionGate()

    private init() {}

    func observeRemoteVoiceHID(
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) {
        lock.lock()
        gate.observeRemoteVoiceHID(
            isDown: isDown,
            eventTimestamp: eventTimestamp,
            observedAt: observedAt
        )
        lock.unlock()
    }

    func decide(
        keyCode: Int,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) -> RemoteVoiceKeySuppressionDecision {
        lock.lock()
        defer { lock.unlock() }
        return gate.decide(
            keyCode: keyCode,
            isDown: isDown,
            eventTimestamp: eventTimestamp,
            observedAt: observedAt
        )
    }

    func reset() {
        lock.lock()
        gate.reset()
        lock.unlock()
    }
}
