import Foundation

enum RemoteMappedEventSuppressionDecision: Equatable {
    case consume
    case pass

    var shouldConsume: Bool {
        self == .consume
    }
}

struct RemoteMappedEventSuppressionGate {
    private struct PendingObservation {
        let button: RemoteButton
        let identity: RemoteSystemEventIdentity
        let isDown: Bool
        let eventTimestamp: UInt64
        let observedAt: UInt64
    }

    let correlationWindowNanoseconds: UInt64
    let maximumHeldNanoseconds: UInt64
    private var pending: [PendingObservation] = []
    private var activeOwnership: [RemoteSystemEventIdentity: UInt64] = [:]

    init(
        correlationWindowNanoseconds: UInt64 = 180_000_000,
        maximumHeldNanoseconds: UInt64 = 310_000_000_000
    ) {
        self.correlationWindowNanoseconds = correlationWindowNanoseconds
        self.maximumHeldNanoseconds = maximumHeldNanoseconds
    }

    mutating func observeRemoteHID(
        button: RemoteButton,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) {
        expire(observedAt: observedAt)
        for identity in RemoteSystemEventProfile.identities(for: button) {
            pending.append(PendingObservation(
                button: button,
                identity: identity,
                isDown: isDown,
                eventTimestamp: eventTimestamp,
                observedAt: observedAt
            ))
        }
        if pending.count > 32 {
            pending.removeFirst(pending.count - 32)
        }
    }

    mutating func decide(
        identity: RemoteSystemEventIdentity,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64,
        eventUserData: Int64,
        isAutoRepeat: Bool
    ) -> RemoteMappedEventSuppressionDecision {
        expire(observedAt: observedAt)
        guard eventUserData == 0 else { return .pass }

        if isDown {
            if let matchIndex = pending.firstIndex(where: {
                $0.identity == identity &&
                    $0.isDown &&
                    correlationDelta(eventTimestamp, $0.eventTimestamp) <= correlationWindowNanoseconds &&
                    correlationDelta(observedAt, $0.observedAt) <= correlationWindowNanoseconds
            }) {
                let match = pending[matchIndex]
                pending.removeAll {
                    $0.button == match.button &&
                        $0.isDown &&
                        $0.eventTimestamp == match.eventTimestamp &&
                        $0.observedAt == match.observedAt
                }
                activeOwnership[identity] = observedAt
                return .consume
            }

            if !isAutoRepeat {
                activeOwnership.removeValue(forKey: identity)
            }
            return .pass
        }

        guard activeOwnership.removeValue(forKey: identity) != nil else {
            return .pass
        }
        pending.removeAll { $0.identity == identity && !$0.isDown }
        return .consume
    }

    mutating func reset() {
        pending.removeAll()
        activeOwnership.removeAll()
    }

    private mutating func expire(observedAt: UInt64) {
        pending.removeAll {
            observedAt >= $0.observedAt &&
                observedAt - $0.observedAt > correlationWindowNanoseconds
        }
        activeOwnership = activeOwnership.filter { _, ownedAt in
            observedAt < ownedAt || observedAt - ownedAt <= maximumHeldNanoseconds
        }
    }

    private func correlationDelta(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}

final class RemoteMappedEventSuppressionRegistry {
    static let shared = RemoteMappedEventSuppressionRegistry()

    private let lock = NSLock()
    private var gate = RemoteMappedEventSuppressionGate()

    private init() {}

    func observeRemoteHID(
        button: RemoteButton,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) {
        lock.lock()
        gate.observeRemoteHID(
            button: button,
            isDown: isDown,
            eventTimestamp: eventTimestamp,
            observedAt: observedAt
        )
        lock.unlock()
    }

    func decide(
        identity: RemoteSystemEventIdentity,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64,
        eventUserData: Int64,
        isAutoRepeat: Bool
    ) -> RemoteMappedEventSuppressionDecision {
        lock.lock()
        defer { lock.unlock() }
        return gate.decide(
            identity: identity,
            isDown: isDown,
            eventTimestamp: eventTimestamp,
            observedAt: observedAt,
            eventUserData: eventUserData,
            isAutoRepeat: isAutoRepeat
        )
    }

    func reset() {
        lock.lock()
        gate.reset()
        lock.unlock()
    }
}
