import Foundation

@main
struct MainCapsuleWaveformMotionCheck {
    static func main() {
        smoothsIncomingBandsWithoutChangingBandCount()
        missingBandsReturnTowardBaseline()
        resetRestoresBaseline()
        print("MainCapsuleWaveformMotionCheck passed")
    }

    private static func smoothsIncomingBandsWithoutChangingBandCount() {
        var motion = MainCapsuleWaveformMotion()
        motion.apply([1.0, 0.5, 0.2])

        precondition(motion.bands.count == 7)
        assertClose(motion.bands[0], 0.5584)
        assertClose(motion.bands[1], 0.2984)
        assertClose(motion.bands[2], 0.1424)
        assertClose(motion.bands[3], 0.08)
    }

    private static func missingBandsReturnTowardBaseline() {
        var motion = MainCapsuleWaveformMotion()
        motion.apply([1.0])
        motion.apply([])

        assertClose(motion.bands[0], 0.481856)
        assertClose(motion.bands[1], 0.08)
    }

    private static func resetRestoresBaseline() {
        var motion = MainCapsuleWaveformMotion(count: 3)
        motion.apply([1.0, 0.5, 0.2])
        motion.reset()

        precondition(motion.bands == [0.08, 0.08, 0.08])
    }

    private static func assertClose(
        _ actual: Float,
        _ expected: Float,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        precondition(abs(actual - expected) < 0.0001, "expected \(expected), got \(actual)", file: file, line: line)
    }
}
