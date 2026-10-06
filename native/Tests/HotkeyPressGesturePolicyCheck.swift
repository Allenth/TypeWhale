import Foundation

@main
struct HotkeyPressGesturePolicyCheck {
    private static let threshold: UInt64 = 450_000_000

    static func main() {
        distinguishesShortAndLongPressesAtThePhysicalBoundary()
        ignoresUnevenBluetoothDeliveryLag()
        keepsLongClassificationWhenTheTimerCallbackIsLate()
        rejectsStaleTimersAndRepeatedDownEvents()
        fallsBackToObservedTimeForOutOfOrderDeviceTimestamps()
        print("HotkeyPressGesturePolicyCheck passed")
    }

    private static func ignoresUnevenBluetoothDeliveryLag() {
        var policy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        _ = policy.begin(at: timing(event: 2_700_000_000, observed: 4_700_000_000))
        precondition(
            policy.release(at: timing(event: 3_000_000_000, observed: 6_000_000_000))
                == .shortPress(durationMilliseconds: 300),
            "classification must use the physical event interval, not uneven Bluetooth delivery delay"
        )
    }

    private static func distinguishesShortAndLongPressesAtThePhysicalBoundary() {
        var shortPolicy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        _ = shortPolicy.begin(at: timing(event: 1_000_000_000, observed: 1_010_000_000))
        precondition(
            shortPolicy.release(at: timing(event: 1_449_999_999, observed: 1_459_999_999))
                == .shortPress(durationMilliseconds: 449)
        )

        var boundaryPolicy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        _ = boundaryPolicy.begin(at: timing(event: 2_000_000_000, observed: 2_015_000_000))
        precondition(
            boundaryPolicy.release(at: timing(event: 2_450_000_000, observed: 2_465_000_000))
                == .longPress(durationMilliseconds: 450, holdActivated: false)
        )
    }

    private static func keepsLongClassificationWhenTheTimerCallbackIsLate() {
        var policy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        _ = policy.begin(at: timing(event: 4_000_000_000, observed: 4_020_000_000))

        precondition(
            policy.release(at: timing(event: 4_780_000_000, observed: 4_800_000_000))
                == .longPress(durationMilliseconds: 780, holdActivated: false),
            "a delayed main-queue timer must never turn a physical long press into toggle recording"
        )
    }

    private static func rejectsStaleTimersAndRepeatedDownEvents() {
        var policy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        let firstID = policy.begin(at: timing(event: 6_000_000_000, observed: 6_010_000_000))
        let repeatedID = policy.begin(at: timing(event: 6_100_000_000, observed: 6_110_000_000))
        precondition(firstID == repeatedID, "key-repeat down must not restart the long-press clock")
        precondition(policy.markHoldActivated(pressID: firstID))
        precondition(
            policy.release(at: timing(event: 6_700_000_000, observed: 6_710_000_000))
                == .longPress(durationMilliseconds: 700, holdActivated: true)
        )
        precondition(!policy.markHoldActivated(pressID: firstID), "released presses must reject stale timers")

        let secondID = policy.begin(at: timing(event: 7_000_000_000, observed: 7_010_000_000))
        precondition(secondID != firstID)
        precondition(!policy.markHoldActivated(pressID: firstID), "a prior timer must not activate a new press")
    }

    private static func fallsBackToObservedTimeForOutOfOrderDeviceTimestamps() {
        var policy = HotkeyPressGesturePolicy(longPressThresholdNanoseconds: threshold)
        _ = policy.begin(at: timing(event: 9_000_000_000, observed: 10_000_000_000))
        precondition(
            policy.release(at: timing(event: 8_900_000_000, observed: 10_600_000_000))
                == .longPress(durationMilliseconds: 600, holdActivated: false),
            "invalid Bluetooth/HID event ordering must fall back to local observation time"
        )
    }

    private static func timing(event: UInt64, observed: UInt64) -> HotkeyEventTiming {
        HotkeyEventTiming(
            eventUptimeNanoseconds: event,
            observedUptimeNanoseconds: observed
        )
    }
}
