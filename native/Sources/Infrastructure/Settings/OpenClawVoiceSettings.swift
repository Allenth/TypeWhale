import Foundation

enum OpenClawVoicePlaybackPolicy: String, CaseIterable {
    case finalReplyOnly
    case manualPreviewOnly

    var displayName: String {
        switch self {
        case .finalReplyOnly: return "只读最终回复"
        case .manualPreviewOnly: return "仅手动试听"
        }
    }
}

enum OpenClawVoiceInterruptPolicy: String, CaseIterable {
    case stopPreviousAndPlayLatest
    case queueReplies
    case doNotInterrupt

    var displayName: String {
        switch self {
        case .stopPreviousAndPlayLatest: return "打断并播放最新"
        case .queueReplies: return "按顺序排队"
        case .doNotInterrupt: return "不打断当前播放"
        }
    }
}

enum OpenClawVoiceEngine: String, CaseIterable {
    case zipVoice = "zipvoice"

    var displayName: String {
        "ZipVoice 本地朗读"
    }

    var relativeDirectory: String {
        "tts/zipvoice-distill-int8-zh-en-emilia"
    }
}

struct OpenClawVoiceSettings: Equatable {
    static let minimumVolume = 0.0
    static let maximumVolume = 1.5
    static let minimumSpeechRate = 0.75
    static let maximumSpeechRate = 1.75
    static let defaultVoiceID = "zipvoice-default"

    static var availableVoices: [TTSLabVoice] {
        let qualified = TTSLabVoiceQualificationStore().qualifiedVoiceIDs(
            modelID: TTSLabVoiceCatalog.retainedModelID,
            fingerprint: TTSLabVoiceCatalog.fingerprintValue
        )
        return TTSLabVoiceCatalog.availableVoices(
            qualifiedVoiceIDs: qualified,
            personalVoice: TTSLabPersonalVoiceStore().discoverVoice()
        )
    }

    static var allowedVoiceIDs: [String] {
        availableVoices.map(\.id)
    }

    static func displayName(for voiceID: String) -> String {
        availableVoices.first(where: { $0.id == voiceID })?.displayName
            ?? TTSLabVoiceCatalog.candidates(for: TTSLabVoiceCatalog.retainedModelID)
                .first(where: { $0.id == voiceID })?.displayName
            ?? "默认新闻女声"
    }

    var enabled: Bool
    var volume: Double
    var speechRate: Double
    var engine: OpenClawVoiceEngine
    var voiceID: String
    var playbackPolicy: OpenClawVoicePlaybackPolicy
    var interruptPolicy: OpenClawVoiceInterruptPolicy

    static let `default` = OpenClawVoiceSettings(
        enabled: false,
        volume: 0.8,
        speechRate: 1.25,
        engine: .zipVoice,
        voiceID: defaultVoiceID,
        playbackPolicy: .finalReplyOnly,
        interruptPolicy: .stopPreviousAndPlayLatest
    )

    var normalized: OpenClawVoiceSettings {
        normalized(availableVoiceIDs: Set(Self.allowedVoiceIDs))
    }

    func normalized(availableVoiceIDs: Set<String>) -> OpenClawVoiceSettings {
        var copy = self
        copy.volume = min(Self.maximumVolume, max(Self.minimumVolume, volume))
        copy.speechRate = min(Self.maximumSpeechRate, max(Self.minimumSpeechRate, speechRate))
        copy.engine = .zipVoice
        if !availableVoiceIDs.contains(copy.voiceID) {
            copy.voiceID = Self.defaultVoiceID
        }
        return copy
    }
}

struct OpenClawVoiceSettingsStore {
    static let standard = OpenClawVoiceSettingsStore()

    private let defaults: UserDefaults
    private let enabledKey = "openClawVoiceEnabled"
    private let volumeKey = "openClawVoiceVolume"
    private let speechRateKey = "openClawVoiceSpeechRate"
    private let engineKey = "openClawVoiceEngine"
    private let voiceIDKey = "openClawVoiceID"
    private let playbackPolicyKey = "openClawVoicePlaybackPolicy"
    private let interruptPolicyKey = "openClawVoiceInterruptPolicy"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(
        availableVoiceIDs: Set<String> = Set(OpenClawVoiceSettings.allowedVoiceIDs)
    ) -> OpenClawVoiceSettings {
        let fallback = OpenClawVoiceSettings.default
        return OpenClawVoiceSettings(
            enabled: defaults.bool(forKey: enabledKey),
            volume: defaults.object(forKey: volumeKey) == nil ? fallback.volume : defaults.double(forKey: volumeKey),
            speechRate: defaults.object(forKey: speechRateKey) == nil ? fallback.speechRate : defaults.double(forKey: speechRateKey),
            engine: .zipVoice,
            voiceID: defaults.string(forKey: voiceIDKey) ?? fallback.voiceID,
            playbackPolicy: OpenClawVoicePlaybackPolicy(rawValue: defaults.string(forKey: playbackPolicyKey) ?? "") ?? fallback.playbackPolicy,
            interruptPolicy: OpenClawVoiceInterruptPolicy(rawValue: defaults.string(forKey: interruptPolicyKey) ?? "") ?? fallback.interruptPolicy
        ).normalized(availableVoiceIDs: availableVoiceIDs)
    }

    func save(
        _ settings: OpenClawVoiceSettings,
        availableVoiceIDs: Set<String> = Set(OpenClawVoiceSettings.allowedVoiceIDs)
    ) {
        let normalized = settings.normalized(availableVoiceIDs: availableVoiceIDs)
        defaults.set(normalized.enabled, forKey: enabledKey)
        defaults.set(normalized.volume, forKey: volumeKey)
        defaults.set(normalized.speechRate, forKey: speechRateKey)
        defaults.set(normalized.engine.rawValue, forKey: engineKey)
        defaults.set(normalized.voiceID, forKey: voiceIDKey)
        defaults.set(normalized.playbackPolicy.rawValue, forKey: playbackPolicyKey)
        defaults.set(normalized.interruptPolicy.rawValue, forKey: interruptPolicyKey)
    }
}
