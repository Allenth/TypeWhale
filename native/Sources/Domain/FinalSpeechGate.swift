import Foundation

enum FinalSpeechGate {
    static func shouldRunFinalASR(
        finalVADDetectedSpeech: Bool?,
        realtimeVoiceDetected: Bool,
        realtimePreviewText: String
    ) -> Bool {
        if finalVADDetectedSpeech == true {
            return true
        }
        if finalVADDetectedSpeech == nil {
            return true
        }
        if realtimeVoiceDetected {
            return true
        }
        return isMeaningfulRecognitionText(realtimePreviewText)
    }
}
