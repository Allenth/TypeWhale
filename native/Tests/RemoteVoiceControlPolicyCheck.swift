import Foundation

@main
struct RemoteVoiceControlPolicyCheck {
    static func main() {
        v10TreatsRepeatedStartSearchAsIdempotent()
        v04PreservesLegacyToggleStopAfterAudioStarts()
        startsFromCorrelatedHIDAndAudioStartInEitherCallbackOrder()
        releaseClearsPendingDirectStartCorrelation()
        toleratesLateAndOutOfOrderControlEvents()
        print("RemoteVoiceControlPolicyCheck passed")
    }

    private static func v10TreatsRepeatedStartSearchAsIdempotent() {
        var policy = RemoteVoiceControlPolicy(usesExplicitAudioStop: true)
        precondition(policy.handle(.startSearch) == .beginSessionAndOpenMicrophone)
        precondition(policy.handle(.startSearch) == .ignoreDuplicateStartSearch)
        precondition(policy.handle(.audioStart) == .none)
        precondition(policy.handle(.startSearch) == .ignoreDuplicateStartSearch)
        precondition(policy.handle(.audioStop) == .finishSession)
        precondition(policy.handle(.audioStop) == .none)
    }

    private static func v04PreservesLegacyToggleStopAfterAudioStarts() {
        var policy = RemoteVoiceControlPolicy(usesExplicitAudioStop: false)
        precondition(policy.handle(.startSearch) == .beginSessionAndOpenMicrophone)
        precondition(
            policy.handle(.startSearch) == .ignoreDuplicateStartSearch,
            "a repeated packet while MIC_OPEN is pending must be harmless"
        )
        precondition(policy.handle(.audioStart) == .none)
        precondition(policy.handle(.startSearch) == .closeMicrophoneAndFinishSession)
        precondition(policy.phase == .idle)
    }

    private static func startsFromCorrelatedHIDAndAudioStartInEitherCallbackOrder() {
        let ms: UInt64 = 1_000_000

        var audioFirst = RemoteVoiceControlPolicy()
        precondition(
            audioFirst.handle(.audioStart, observedAt: 1_000 * ms) == .awaitCorrelatedVoiceButton
        )
        precondition(
            audioFirst.observeVoiceButton(isDown: true, observedAt: 1_001 * ms) == .beginSessionFromAudioStart
        )
        precondition(audioFirst.phase == .streaming)
        precondition(audioFirst.handle(.audioStop, observedAt: 1_500 * ms) == .finishSession)

        var hidFirst = RemoteVoiceControlPolicy()
        precondition(hidFirst.observeVoiceButton(isDown: true, observedAt: 2_000 * ms) == .none)
        precondition(
            hidFirst.handle(.audioStart, observedAt: 2_001 * ms) == .beginSessionFromAudioStart
        )
        precondition(hidFirst.phase == .streaming)
        precondition(hidFirst.handle(.audioStop, observedAt: 2_500 * ms) == .finishSession)
    }

    private static func releaseClearsPendingDirectStartCorrelation() {
        let ms: UInt64 = 1_000_000
        var policy = RemoteVoiceControlPolicy()
        precondition(
            policy.handle(.audioStart, observedAt: 4_000 * ms) == .awaitCorrelatedVoiceButton
        )
        precondition(policy.observeVoiceButton(isDown: false, observedAt: 4_001 * ms) == .none)
        precondition(
            policy.observeVoiceButton(isDown: true, observedAt: 4_002 * ms) == .none,
            "a release must prevent an old AUDIO_START from attaching to the next physical press"
        )
        precondition(policy.phase == .idle)
    }

    private static func toleratesLateAndOutOfOrderControlEvents() {
        let ms: UInt64 = 1_000_000
        var policy = RemoteVoiceControlPolicy(usesExplicitAudioStop: true)
        precondition(policy.handle(.startSearch) == .beginSessionAndOpenMicrophone)
        precondition(policy.handle(.audioStop) == .finishSession)
        precondition(
            policy.handle(.audioStart, observedAt: 3_000 * ms) == .awaitCorrelatedVoiceButton,
            "an idle AUDIO_START may wait briefly for the real RC003 HID callback"
        )
        precondition(
            policy.observeVoiceButton(isDown: true, observedAt: 3_500 * ms) == .none,
            "an out-of-window HID event must not turn a late AUDIO_START into an orphaned session"
        )
        precondition(policy.handle(.audioStop) == .none)
        precondition(policy.handle(.startSearch) == .beginSessionAndOpenMicrophone)
        precondition(policy.handle(.audioStart) == .none)
        precondition(policy.handle(.audioStop) == .finishSession)
        policy.reset()
        precondition(policy.phase == .idle)
    }
}
