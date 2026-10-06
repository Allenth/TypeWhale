import Foundation

@main
struct RecordingAutoFinishPolicyCheck {
    private static func assertPauseFinish(
        _ decision: RecordingAutoFinishDecision,
        expected: TimeInterval
    ) {
        guard case .finishAfterPause(let actual) = decision,
              abs(actual - expected) < 0.001 else {
            preconditionFailure("expected pause finish near \(expected), got \(decision)")
        }
    }

    private static func assertInitialCancel(
        _ decision: RecordingAutoFinishDecision,
        expected: TimeInterval,
        message: String = ""
    ) {
        guard case .cancelInitialSilence(let actual) = decision,
              abs(actual - expected) < 0.001 else {
            preconditionFailure("expected initial cancel near \(expected), got \(decision). \(message)")
        }
    }

    static func main() {
        let start = Date(timeIntervalSince1970: 1_000)

        var disabledPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        disabledPolicy.reset(startedAt: start)
        precondition(disabledPolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(1),
            autoFinishEnabled: false,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording)
        precondition(disabledPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(3),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        assertPauseFinish(disabledPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(3.4),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ), expected: 2.4)

        var holdPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        holdPolicy.reset(startedAt: start)
        _ = holdPolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(1),
            autoFinishEnabled: true,
            isHoldActivation: true,
            hasMeaningfulPreview: false
        )
        precondition(holdPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(4),
            autoFinishEnabled: true,
            isHoldActivation: true,
            hasMeaningfulPreview: false
        ) == .continueRecording)

        var pausePolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        pausePolicy.reset(startedAt: start)
        precondition(pausePolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(1),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording)
        precondition(pausePolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(2.4),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording)
        precondition(pausePolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(2.5),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        assertPauseFinish(pausePolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(2.9),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ), expected: 1.9)
        precondition(pausePolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(3.3),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording, "a decision must only be emitted once")

        var initialPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        initialPolicy.reset(startedAt: start)
        for elapsed in [3.0, 7.9] {
            precondition(initialPolicy.evaluateProbe(
                hasSpeech: false,
                capturedAt: start.addingTimeInterval(elapsed),
                autoFinishEnabled: true,
                isHoldActivation: false,
                hasMeaningfulPreview: false
            ) == .continueRecording)
        }
        precondition(initialPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(8),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        assertInitialCancel(initialPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(8.4),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ), expected: 8.4)

        var previewPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        previewPolicy.reset(startedAt: start)
        precondition(previewPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(8.5),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: true
        ) == .continueRecording)
        precondition(previewPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(9),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording, "preview speech evidence must not be forgotten if a later preview snapshot is empty")

        previewPolicy.reset(startedAt: start.addingTimeInterval(20))
        precondition(previewPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(28),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        assertInitialCancel(previewPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(28.4),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ), expected: 8.4, message: "reset must begin a clean recording session")

        var resumedSpeechPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        resumedSpeechPolicy.reset(startedAt: start)
        _ = resumedSpeechPolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(1),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        )
        precondition(resumedSpeechPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(2.5),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        precondition(resumedSpeechPolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(2.8),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .continueRecording, "speech after a silence candidate must cancel auto-finish")
        precondition(resumedSpeechPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(4.3),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ) == .awaitingNoSpeechConfirmation)
        assertPauseFinish(resumedSpeechPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(4.7),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false
        ), expected: 1.9)

        var queuedSpeechPolicy = RecordingAutoFinishPolicy(pauseSeconds: 1.5, initialSilenceSeconds: 8)
        queuedSpeechPolicy.reset(startedAt: start)
        precondition(queuedSpeechPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(8),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false,
            canCommitDecision: false
        ) == .awaitingNoSpeechConfirmation)
        precondition(queuedSpeechPolicy.evaluateProbe(
            hasSpeech: false,
            capturedAt: start.addingTimeInterval(8.4),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false,
            canCommitDecision: false
        ) == .deferredForNewerAudio, "two old silence results must not finish while a newer speech window is queued")
        precondition(queuedSpeechPolicy.evaluateProbe(
            hasSpeech: true,
            capturedAt: start.addingTimeInterval(8.8),
            autoFinishEnabled: true,
            isHoldActivation: false,
            hasMeaningfulPreview: false,
            canCommitDecision: true
        ) == .continueRecording, "queued speech must be processed before any finish decision")

        print("RecordingAutoFinishPolicyCheck passed")
    }
}
