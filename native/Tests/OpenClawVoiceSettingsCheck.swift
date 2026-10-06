import Foundation

@main
struct OpenClawVoiceSettingsCheck {
    static func main() {
        let suiteName = "TypeWhale.OpenClawVoiceSettingsCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("failed to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = OpenClawVoiceSettingsStore(defaults: defaults)
        let initial = store.load()
        precondition(initial.enabled == false, "OpenClaw voice must be opt-in")
        precondition(initial.volume == 0.8, "default voice volume should be comfortable")
        precondition(initial.speechRate == 1.25, "OpenClaw voice should default to brisk playback")
        precondition(initial.engine == .zipVoice)
        precondition(OpenClawVoiceEngine.allCases == [.zipVoice])
        precondition(OpenClawVoiceEngine.zipVoice.rawValue == "zipvoice")
        precondition(initial.voiceID == "zipvoice-default")
        precondition(initial.playbackPolicy == .finalReplyOnly, "default playback should avoid reading transport/status events")
        precondition(initial.interruptPolicy == .stopPreviousAndPlayLatest, "default interrupt policy should keep the latest reply audible")

        for legacyValue in ["melotts", "sherpa_melo_44k", "sherpa_melo_native"] {
            defaults.set(legacyValue, forKey: "openClawVoiceEngine")
            precondition(store.load().engine == .zipVoice)
        }
        defaults.set("missing", forKey: "openClawVoiceID")
        precondition(
            store.load(availableVoiceIDs: ["zipvoice-default"]).voiceID == "zipvoice-default",
            "invalid voices must fall back to the stable ZipVoice default"
        )

        let availableVoiceIDs: Set<String> = [
            "zipvoice-default",
            "zipvoice-serena",
            "zipvoice-cosy",
            "zipvoice-video-reference",
            "zipvoice-my-voice",
        ]
        for voiceID in availableVoiceIDs {
            store.save(OpenClawVoiceSettings(
                enabled: true,
                volume: 2.0,
                speechRate: 2.5,
                engine: .zipVoice,
                voiceID: voiceID,
                playbackPolicy: .finalReplyOnly,
                interruptPolicy: .queueReplies
            ), availableVoiceIDs: availableVoiceIDs)
            let saved = store.load(availableVoiceIDs: availableVoiceIDs)
            precondition(saved.enabled)
            precondition(saved.volume == 1.5)
            precondition(saved.speechRate == 1.75)
            precondition(saved.engine == .zipVoice)
            precondition(saved.voiceID == voiceID)
            precondition(saved.interruptPolicy == .queueReplies)
        }

        defaults.removePersistentDomain(forName: suiteName)
    }
}
