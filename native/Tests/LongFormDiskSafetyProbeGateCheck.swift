import Foundation

@main
struct LongFormDiskSafetyProbeGateCheck {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_000)
        var gate = LongFormDiskSafetyProbeGate(minimumInterval: 30)

        precondition(gate.beginIfDue(at: start), "the first disk safety probe should run immediately")
        precondition(!gate.beginIfDue(at: start.addingTimeInterval(1)), "an in-flight probe must not overlap")

        gate.complete()
        precondition(!gate.beginIfDue(at: start.addingTimeInterval(29.9)), "audio callbacks must not retrigger the disk probe inside the interval")
        precondition(gate.beginIfDue(at: start.addingTimeInterval(30)), "the probe should become due at the configured interval")

        gate.complete()
        gate.reset()
        precondition(gate.beginIfDue(at: start.addingTimeInterval(31)), "a new recording session should be allowed an immediate probe")

        print("LongFormDiskSafetyProbeGateCheck passed")
    }
}
