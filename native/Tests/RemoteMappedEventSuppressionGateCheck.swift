import Foundation

@main
enum RemoteMappedEventSuppressionGateCheck {
    private static let ms: UInt64 = 1_000_000

    static func main() {
        verifiesRC003SystemEventProfile()
        consumesOnlyCorrelatedKeyboardEvents()
        ignoresSyntheticEventsWithoutDisarming()
        consumesThePairedUpEvenWhenHIDUpArrivesLater()
        releasesOwnershipForAnUncorrelatedPhysicalDown()
        consumesCorrelatedSystemDefinedEvents()
        expiresAndResetsSafely()
        print("RemoteMappedEventSuppressionGateCheck passed")
    }

    private static func verifiesRC003SystemEventProfile() {
        precondition(RemoteSystemEventProfile.identities(for: .dpadUp) == [.keyboard(keyCode: 126)])
        precondition(RemoteSystemEventProfile.identities(for: .center) == [.keyboard(keyCode: 36)])
        precondition(RemoteSystemEventProfile.identities(for: .menu) == [.keyboard(keyCode: 110)])
        precondition(RemoteSystemEventProfile.identities(for: .power) == [.keyboard(keyCode: 90)])
        precondition(RemoteSystemEventProfile.identities(for: .volumeUp) == [.systemDefined(keyType: 0)])
        precondition(RemoteSystemEventProfile.identities(for: .volumeDown) == [.systemDefined(keyType: 1)])
        precondition(RemoteSystemEventProfile.identities(for: .tv) == [
            .keyboard(keyCode: 10),
            .keyboard(keyCode: 50),
        ])
        precondition(RemoteSystemEventProfile.identities(for: .back).isEmpty)
        precondition(RemoteSystemEventProfile.identities(for: .voice).isEmpty)
    }

    private static func consumesOnlyCorrelatedKeyboardEvents() {
        var gate = RemoteMappedEventSuppressionGate()
        gate.observeRemoteHID(
            button: .dpadUp,
            isDown: true,
            eventTimestamp: 1_000 * ms,
            observedAt: 1_010 * ms
        )
        precondition(gate.decide(
            identity: .keyboard(keyCode: 125),
            isDown: true,
            eventTimestamp: 1_015 * ms,
            observedAt: 1_020 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .pass)
        precondition(gate.decide(
            identity: .keyboard(keyCode: 126),
            isDown: true,
            eventTimestamp: 1_015 * ms,
            observedAt: 1_020 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
    }

    private static func ignoresSyntheticEventsWithoutDisarming() {
        var gate = RemoteMappedEventSuppressionGate()
        gate.observeRemoteHID(
            button: .center,
            isDown: true,
            eventTimestamp: 2_000 * ms,
            observedAt: 2_010 * ms
        )
        precondition(gate.decide(
            identity: .keyboard(keyCode: 36),
            isDown: true,
            eventTimestamp: 2_015 * ms,
            observedAt: 2_020 * ms,
            eventUserData: RemoteSyntheticKeyEventSpec.userData,
            isAutoRepeat: false
        ) == .pass)
        precondition(gate.decide(
            identity: .keyboard(keyCode: 36),
            isDown: true,
            eventTimestamp: 2_016 * ms,
            observedAt: 2_021 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
    }

    private static func consumesThePairedUpEvenWhenHIDUpArrivesLater() {
        var gate = RemoteMappedEventSuppressionGate()
        gate.observeRemoteHID(
            button: .dpadLeft,
            isDown: true,
            eventTimestamp: 3_000 * ms,
            observedAt: 3_010 * ms
        )
        precondition(gate.decide(
            identity: .keyboard(keyCode: 123),
            isDown: true,
            eventTimestamp: 3_005 * ms,
            observedAt: 3_015 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
        precondition(gate.decide(
            identity: .keyboard(keyCode: 123),
            isDown: false,
            eventTimestamp: 3_200 * ms,
            observedAt: 3_210 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
    }

    private static func releasesOwnershipForAnUncorrelatedPhysicalDown() {
        var gate = RemoteMappedEventSuppressionGate()
        gate.observeRemoteHID(
            button: .dpadRight,
            isDown: true,
            eventTimestamp: 4_000 * ms,
            observedAt: 4_010 * ms
        )
        precondition(gate.decide(
            identity: .keyboard(keyCode: 124),
            isDown: true,
            eventTimestamp: 4_005 * ms,
            observedAt: 4_015 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
        precondition(gate.decide(
            identity: .keyboard(keyCode: 124),
            isDown: true,
            eventTimestamp: 4_500 * ms,
            observedAt: 4_510 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .pass)
        precondition(gate.decide(
            identity: .keyboard(keyCode: 124),
            isDown: false,
            eventTimestamp: 4_550 * ms,
            observedAt: 4_560 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .pass)
    }

    private static func consumesCorrelatedSystemDefinedEvents() {
        var gate = RemoteMappedEventSuppressionGate()
        gate.observeRemoteHID(
            button: .volumeUp,
            isDown: true,
            eventTimestamp: 5_000 * ms,
            observedAt: 5_010 * ms
        )
        precondition(gate.decide(
            identity: .systemDefined(keyType: 0),
            isDown: true,
            eventTimestamp: 5_005 * ms,
            observedAt: 5_015 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .consume)
    }

    private static func expiresAndResetsSafely() {
        var gate = RemoteMappedEventSuppressionGate(correlationWindowNanoseconds: 100 * ms)
        gate.observeRemoteHID(
            button: .home,
            isDown: true,
            eventTimestamp: 6_000 * ms,
            observedAt: 6_010 * ms
        )
        precondition(gate.decide(
            identity: .keyboard(keyCode: 115),
            isDown: true,
            eventTimestamp: 6_005 * ms,
            observedAt: 6_200 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .pass)
        gate.observeRemoteHID(
            button: .home,
            isDown: true,
            eventTimestamp: 7_000 * ms,
            observedAt: 7_010 * ms
        )
        gate.reset()
        precondition(gate.decide(
            identity: .keyboard(keyCode: 115),
            isDown: true,
            eventTimestamp: 7_005 * ms,
            observedAt: 7_015 * ms,
            eventUserData: 0,
            isAutoRepeat: false
        ) == .pass)
    }
}
