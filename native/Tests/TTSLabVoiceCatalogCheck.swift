import Foundation

@main
enum TTSLabVoiceCatalogCheck {
    static func main() {
        let zipVoice = TTSLabVoiceCatalog.candidates(
            for: "zipvoice-distill-int8-zh-en-emilia"
        )

        precondition(zipVoice.map(\.id) == [
            "zipvoice-default",
            "zipvoice-serena",
            "zipvoice-cosy",
            "zipvoice-video-reference",
        ])
        precondition(zipVoice.first?.isDefault == true)
        let personalVoice = TTSLabVoice(
            id: "zipvoice-my-voice",
            displayName: "我的声音",
            detail: "本机录制 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: false
        )
        let available = TTSLabVoiceCatalog.availableVoices(
            qualifiedVoiceIDs: Set(zipVoice.map(\.id)),
            personalVoice: personalVoice
        )
        precondition(available.map(\.id) == [
            "zipvoice-default",
            "zipvoice-serena",
            "zipvoice-cosy",
            "zipvoice-video-reference",
            "zipvoice-my-voice",
        ])
        precondition(
            TTSLabVoiceCatalog.availableVoices(
                qualifiedVoiceIDs: Set(zipVoice.map(\.id)),
                personalVoice: nil
            ).map(\.id) == zipVoice.map(\.id)
        )
        precondition(
            TTSLabVoiceCatalog.availableVoices(
                qualifiedVoiceIDs: ["zipvoice-default", "missing"],
                personalVoice: nil
            ).map(\.id) == ["zipvoice-default"]
        )
        precondition(
            TTSLabVoiceCatalog.fingerprint(
                for: "zipvoice-distill-int8-zh-en-emilia"
            ) == "zipvoice-distill-int8-reference-voices-v2"
        )

        precondition(TTSLabVoiceCatalog.candidates(for: "sherpa-vits-melo-tts-zh_en").isEmpty)
        precondition(TTSLabVoiceCatalog.candidates(for: "qwen3-tts-06b-coreml").isEmpty)
        precondition(TTSLabVoiceCatalog.candidates(for: "qwen3-tts-17b-coreml").isEmpty)
        precondition(TTSLabVoiceCatalog.candidates(for: "kokoro-int8-multi-lang-v1_1").isEmpty)
        print("TTSLabVoiceCatalogCheck passed")
    }
}
