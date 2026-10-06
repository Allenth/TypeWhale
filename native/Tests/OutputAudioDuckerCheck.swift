import CoreAudio
import Foundation

private final class ManualDuckerScheduler {
    private var workItems: [DispatchWorkItem] = []

    func schedule(after _: TimeInterval, _ workItem: DispatchWorkItem) {
        workItems.append(workItem)
    }

    func runAll() {
        var index = 0
        while index < workItems.count {
            let workItem = workItems[index]
            index += 1
            workItem.perform()
        }
        workItems.removeAll()
    }
}

@main
struct OutputAudioDuckerCheck {
    static func main() {
        preservesFirstBaselineAcrossConsecutiveRecordings()
        respectsUserVolumeAndUsesItAsNextBaseline()
        disabledStartDoesNotCancelPendingRestore()
        print("OutputAudioDuckerCheck passed")
    }

    private static func preservesFirstBaselineAcrossConsecutiveRecordings() {
        let scheduler = ManualDuckerScheduler()
        var volume: Float32 = 0.70
        let control = OutputAudioDucker.VolumeControl(deviceID: 42, element: 0)
        let ducker = makeDucker(control: control, volume: { volume }, setVolume: { volume = $0 }, scheduler: scheduler)

        ducker.duckIfNeeded(enabled: true)
        precondition(abs(volume - 0.0) < 0.001, "first recording must mute 70% to 0%")
        ducker.restore()
        ducker.duckIfNeeded(enabled: true)
        precondition(abs(volume - 0.0) < 0.001, "second recording must remain muted")
        ducker.restore()
        scheduler.runAll()

        precondition(abs(volume - 0.70) < 0.001, "final restore must return to the first 70% baseline, got \(volume)")
        precondition(!ducker.isDucking, "completed restore must release volume ownership")
    }

    private static func respectsUserVolumeAndUsesItAsNextBaseline() {
        let scheduler = ManualDuckerScheduler()
        var volume: Float32 = 0.70
        let control = OutputAudioDucker.VolumeControl(deviceID: 43, element: 0)
        let ducker = makeDucker(control: control, volume: { volume }, setVolume: { volume = $0 }, scheduler: scheduler)

        ducker.duckIfNeeded(enabled: true)
        volume = 0.40
        ducker.restore()
        scheduler.runAll()
        precondition(abs(volume - 0.40) < 0.001, "restore must preserve a user-selected 40% volume")

        ducker.duckIfNeeded(enabled: true)
        ducker.restore()
        scheduler.runAll()
        precondition(abs(volume - 0.40) < 0.001, "the next recording must restore to the user's 40% baseline")
    }

    private static func disabledStartDoesNotCancelPendingRestore() {
        let scheduler = ManualDuckerScheduler()
        var volume: Float32 = 0.65
        let control = OutputAudioDucker.VolumeControl(deviceID: 44, element: 0)
        let ducker = makeDucker(control: control, volume: { volume }, setVolume: { volume = $0 }, scheduler: scheduler)

        ducker.duckIfNeeded(enabled: true)
        ducker.restore()
        ducker.duckIfNeeded(enabled: false)
        scheduler.runAll()

        precondition(abs(volume - 0.65) < 0.001, "a disabled future start must not strand a pending muted volume")
    }

    private static func makeDucker(
        control: OutputAudioDucker.VolumeControl,
        volume: @escaping () -> Float32,
        setVolume: @escaping (Float32) -> Void,
        scheduler: ManualDuckerScheduler
    ) -> OutputAudioDucker {
        OutputAudioDucker(
            controls: { [control] },
            readVolume: { _ in volume() },
            writeVolume: { value, _ in setVolume(value) },
            schedule: scheduler.schedule
        )
    }
}
