import Foundation

@main
struct RemoteVoiceKeySuppressionGateCheck {
    private static let ms: UInt64 = 1_000_000

    static func main() {
        passesPhysicalF5AndEveryOtherKeyWhenUnarmed()
        consumesOnlyTheCorrelatedRemoteVoiceF5Pair()
        supportsHIDUpArrivingBeforeTheCGEventPair()
        consumesCGUpWhenTheHIDUpCallbackIsLate()
        keepsAFullLengthRemoteRecordingSuppressed()
        expiresMissingAndOutOfWindowEvents()
        resetCannotLeaveF5Suppressed()
        print("RemoteVoiceKeySuppressionGateCheck passed")
    }

    private static func passesPhysicalF5AndEveryOtherKeyWhenUnarmed() {
        var gate = RemoteVoiceKeySuppressionGate()
        precondition(gate.decide(keyCode: 96, isDown: true, eventTimestamp: 1_000 * ms, observedAt: 1_010 * ms) == .pass)
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 2_000 * ms, observedAt: 2_010 * ms)
        precondition(gate.decide(keyCode: 36, isDown: true, eventTimestamp: 2_001 * ms, observedAt: 2_012 * ms) == .pass)
    }

    private static func consumesOnlyTheCorrelatedRemoteVoiceF5Pair() {
        var gate = RemoteVoiceKeySuppressionGate()
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 3_000 * ms, observedAt: 3_010 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 3_003 * ms, observedAt: 3_014 * ms)
                == .consumeRemoteVoiceDown(correlationMilliseconds: 3)
        )
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 3_200 * ms, observedAt: 3_210 * ms).shouldConsume,
            "F5 key-repeat from a held remote voice button must stay suppressed"
        )
        gate.observeRemoteVoiceHID(isDown: false, eventTimestamp: 3_600 * ms, observedAt: 3_610 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: false, eventTimestamp: 3_602 * ms, observedAt: 3_612 * ms)
                == .consumeRemoteVoiceUp(correlationMilliseconds: 2)
        )
        precondition(gate.decide(keyCode: 96, isDown: false, eventTimestamp: 3_603 * ms, observedAt: 3_613 * ms) == .pass)
    }

    private static func supportsHIDUpArrivingBeforeTheCGEventPair() {
        var gate = RemoteVoiceKeySuppressionGate()
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 4_000 * ms, observedAt: 4_010 * ms)
        gate.observeRemoteVoiceHID(isDown: false, eventTimestamp: 4_080 * ms, observedAt: 4_090 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 4_002 * ms, observedAt: 4_100 * ms)
                == .consumeRemoteVoiceDown(correlationMilliseconds: 2)
        )
        precondition(
            gate.decide(keyCode: 96, isDown: false, eventTimestamp: 4_082 * ms, observedAt: 4_102 * ms)
                == .consumeRemoteVoiceUp(correlationMilliseconds: 2)
        )
    }

    private static func consumesCGUpWhenTheHIDUpCallbackIsLate() {
        var gate = RemoteVoiceKeySuppressionGate()
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 4_500 * ms, observedAt: 4_510 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 4_502 * ms, observedAt: 4_512 * ms).shouldConsume
        )
        precondition(
            gate.decide(keyCode: 96, isDown: false, eventTimestamp: 5_000 * ms, observedAt: 5_010 * ms).shouldConsume,
            "the matched F5 up must be consumed even if the parallel IOHID up callback arrives later"
        )
        gate.observeRemoteVoiceHID(isDown: false, eventTimestamp: 5_001 * ms, observedAt: 5_011 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 5_020 * ms, observedAt: 5_030 * ms) == .pass,
            "a late HID up must not re-arm suppression after the correlated CGEvent pair completed"
        )
    }

    private static func keepsAFullLengthRemoteRecordingSuppressed() {
        var gate = RemoteVoiceKeySuppressionGate()
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 10_000 * ms, observedAt: 10_010 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 10_002 * ms, observedAt: 10_012 * ms).shouldConsume
        )
        precondition(
            gate.decide(keyCode: 96, isDown: false, eventTimestamp: 309_000 * ms, observedAt: 309_010 * ms).shouldConsume,
            "the remote voice key must remain paired for TypeWhale's full five-minute recording window"
        )
    }

    private static func expiresMissingAndOutOfWindowEvents() {
        var gate = RemoteVoiceKeySuppressionGate(
            correlationWindowNanoseconds: 120 * ms,
            maximumHeldNanoseconds: 30_000 * ms
        )
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 5_000 * ms, observedAt: 5_010 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: true, eventTimestamp: 5_500 * ms, observedAt: 5_510 * ms) == .pass,
            "an unrelated physical F5 outside the correlation window must pass"
        )

        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 6_000 * ms, observedAt: 6_010 * ms)
        _ = gate.decide(keyCode: 96, isDown: true, eventTimestamp: 6_002 * ms, observedAt: 6_012 * ms)
        precondition(
            gate.decide(keyCode: 96, isDown: false, eventTimestamp: 40_000 * ms, observedAt: 40_010 * ms) == .pass,
            "a lost remote key-up must not leave physical F5 suppressed indefinitely"
        )
    }

    private static func resetCannotLeaveF5Suppressed() {
        var gate = RemoteVoiceKeySuppressionGate()
        gate.observeRemoteVoiceHID(isDown: true, eventTimestamp: 50_000 * ms, observedAt: 50_010 * ms)
        gate.reset()
        precondition(gate.decide(keyCode: 96, isDown: true, eventTimestamp: 50_002 * ms, observedAt: 50_012 * ms) == .pass)
    }
}
