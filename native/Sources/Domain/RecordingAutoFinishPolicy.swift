import Foundation

enum RecordingAutoFinishDecision: Equatable {
    case continueRecording
    case awaitingNoSpeechConfirmation
    case deferredForNewerAudio
    case finishAfterPause(silenceDuration: TimeInterval)
    case cancelInitialSilence(elapsed: TimeInterval)
}

struct RecordingAutoFinishPolicy {
    let pauseSeconds: TimeInterval
    let initialSilenceSeconds: TimeInterval

    private var recordingStartedAt: Date?
    private var lastVoiceAt: Date?
    private var voiceEverDetected = false
    private var previewEvidenceEverDetected = false
    private var pendingNoSpeechCapturedAt: Date?
    private var hasFinished = false

    init(pauseSeconds: TimeInterval, initialSilenceSeconds: TimeInterval) {
        self.pauseSeconds = pauseSeconds
        self.initialSilenceSeconds = initialSilenceSeconds
    }

    mutating func reset(startedAt: Date) {
        recordingStartedAt = startedAt
        lastVoiceAt = nil
        voiceEverDetected = false
        previewEvidenceEverDetected = false
        pendingNoSpeechCapturedAt = nil
        hasFinished = false
    }

    mutating func evaluateProbe(
        hasSpeech: Bool,
        capturedAt: Date,
        autoFinishEnabled: Bool,
        isHoldActivation: Bool,
        hasMeaningfulPreview: Bool,
        canCommitDecision: Bool = true
    ) -> RecordingAutoFinishDecision {
        guard !hasFinished else { return .continueRecording }

        if hasSpeech {
            voiceEverDetected = true
            lastVoiceAt = capturedAt
            pendingNoSpeechCapturedAt = nil
        }
        if hasMeaningfulPreview {
            previewEvidenceEverDetected = true
        }

        guard autoFinishEnabled, !isHoldActivation, !hasSpeech else {
            if !autoFinishEnabled || isHoldActivation {
                pendingNoSpeechCapturedAt = nil
            }
            return .continueRecording
        }

        let proposedDecision: RecordingAutoFinishDecision
        if voiceEverDetected {
            guard let lastVoiceAt else {
                pendingNoSpeechCapturedAt = nil
                return .continueRecording
            }
            let silenceDuration = capturedAt.timeIntervalSince(lastVoiceAt)
            guard silenceDuration >= pauseSeconds else {
                pendingNoSpeechCapturedAt = nil
                return .continueRecording
            }
            proposedDecision = .finishAfterPause(silenceDuration: silenceDuration)
        } else {
            guard !previewEvidenceEverDetected,
                  let recordingStartedAt else {
                pendingNoSpeechCapturedAt = nil
                return .continueRecording
            }
            let elapsed = capturedAt.timeIntervalSince(recordingStartedAt)
            guard elapsed >= initialSilenceSeconds else {
                pendingNoSpeechCapturedAt = nil
                return .continueRecording
            }
            proposedDecision = .cancelInitialSilence(elapsed: elapsed)
        }

        guard let pendingNoSpeechCapturedAt,
              capturedAt > pendingNoSpeechCapturedAt else {
            self.pendingNoSpeechCapturedAt = capturedAt
            return .awaitingNoSpeechConfirmation
        }
        guard canCommitDecision else {
            return .deferredForNewerAudio
        }
        self.pendingNoSpeechCapturedAt = nil
        hasFinished = true
        return proposedDecision
    }
}
