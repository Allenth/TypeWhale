import Foundation

@main
struct FinalSpeechGateCheck {
    static func main() {
        precondition(FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: true,
            realtimeVoiceDetected: false,
            realtimePreviewText: ""
        ), "final VAD speech should run final ASR")

        precondition(FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: nil,
            realtimeVoiceDetected: false,
            realtimePreviewText: ""
        ), "VAD failure should not block final ASR")

        precondition(FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: false,
            realtimeVoiceDetected: true,
            realtimePreviewText: ""
        ), "recording-time voice evidence should override final no_speech")

        precondition(FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: false,
            realtimeVoiceDetected: false,
            realtimePreviewText: "这里已经有实时预览文本"
        ), "visible realtime preview text should override final no_speech")

        precondition(!FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: false,
            realtimeVoiceDetected: false,
            realtimePreviewText: ""
        ), "no speech evidence should keep empty-recording behavior")

        precondition(!FinalSpeechGate.shouldRunFinalASR(
            finalVADDetectedSpeech: false,
            realtimeVoiceDetected: false,
            realtimePreviewText: "嗯"
        ), "common silence hallucination should not override final no_speech")

        print("FinalSpeechGateCheck passed")
    }
}
