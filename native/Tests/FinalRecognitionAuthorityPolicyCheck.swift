import Foundation

enum ASRBackend {
    case senseVoice
    case funASRNano
}

@main
struct FinalRecognitionAuthorityPolicyCheck {
    static func main() {
        precondition(
            FinalRecognitionAuthorityPolicy.action(
                backend: .senseVoice,
                reRecognizeWholeRecordingAfterStop: false,
                realtimeCacheReady: true
            ) == .useRealtimeCache
        )
        precondition(
            FinalRecognitionAuthorityPolicy.action(
                backend: .senseVoice,
                reRecognizeWholeRecordingAfterStop: true,
                realtimeCacheReady: true
            ) == .runSelectedBackend
        )
        precondition(
            FinalRecognitionAuthorityPolicy.action(
                backend: .senseVoice,
                reRecognizeWholeRecordingAfterStop: false,
                realtimeCacheReady: false
            ) == .realtimeCacheUnavailable
        )
        precondition(
            FinalRecognitionAuthorityPolicy.action(
                backend: .funASRNano,
                reRecognizeWholeRecordingAfterStop: false,
                realtimeCacheReady: true
            ) == .runSelectedBackend
        )
        precondition(
            FinalRecognitionAuthorityPolicy.action(
                backend: .funASRNano,
                reRecognizeWholeRecordingAfterStop: false,
                realtimeCacheReady: false
            ) == .runSelectedBackend
        )
        print("FinalRecognitionAuthorityPolicyCheck passed")
    }
}
