import AppKit
import Foundation

enum RecognitionLanguageMode: String, CaseIterable {
    case chinese

    static let defaultsKey = "recognitionLanguageMode"

    static func load() -> RecognitionLanguageMode {
        .chinese
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        }
    }

    var senseVoiceLanguage: String {
        switch self {
        case .chinese: return "auto"
        }
    }

    var segmentedIndex: Int {
        switch self {
        case .chinese: return 0
        }
    }

    static func fromSegmentedIndex(_ index: Int) -> RecognitionLanguageMode {
        .chinese
    }
}

enum ASRBackend: String, CaseIterable, Codable {
    case senseVoice
    case parakeetSherpa
    case funASRNano
    case qwen3MLX06B
    case qwen3MLX17B

    static let defaultsKey = "asrBackend"
    private static let retiredRawValues: Set<String> = [
        "zipformerSherpa",
        "qwen3Sherpa",
        "paraformerContextual",
        "paraformerZH",
        "seacoParaformer",
        "whisperSmallMLX",
        "whisperTinyMLX",
        "qwen3ASR",
    ]

    static func load() -> ASRBackend {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        if let backend = ASRBackend(rawValue: rawValue) {
            return backend
        }
        let migratedBackend: ASRBackend?
        switch rawValue {
        case "qwen3ASR06BMLX8Bit": migratedBackend = .qwen3MLX06B
        case "qwen3ASR17BMLX8Bit": migratedBackend = .qwen3MLX17B
        default: migratedBackend = nil
        }
        if let migratedBackend {
            UserDefaults.standard.set(migratedBackend.rawValue, forKey: defaultsKey)
            return migratedBackend
        }
        if retiredRawValues.contains(rawValue) || rawValue == "automatic" {
            UserDefaults.standard.set(ASRBackend.senseVoice.rawValue, forKey: defaultsKey)
        }
        return .senseVoice
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var displayName: String {
        switch self {
        case .senseVoice: return "SenseVoice int8"
        case .parakeetSherpa: return "Parakeet TDT 0.6B v2 · Sherpa int8"
        case .funASRNano: return "Fun-ASR Nano"
        case .qwen3MLX06B: return "Qwen3-ASR 0.6B · MLX 8-bit"
        case .qwen3MLX17B: return "Qwen3-ASR 1.7B · MLX 8-bit"
        }
    }

    var menuTag: Int {
        switch self {
        case .senseVoice: return 0
        case .parakeetSherpa: return 1
        case .funASRNano: return 2
        case .qwen3MLX06B: return 3
        case .qwen3MLX17B: return 4
        }
    }

    var candidateID: ASRCandidateID {
        switch self {
        case .senseVoice: return .senseVoiceInt8
        case .parakeetSherpa: return .parakeetTDT06B
        case .funASRNano: return .funASRNano2512
        case .qwen3MLX06B: return .qwen3MLX06B
        case .qwen3MLX17B: return .qwen3MLX17B
        }
    }

    var resolvedBackend: ASRBackend {
        self
    }

    var supportsFunASRSidecarWarmup: Bool {
        switch self {
        case .funASRNano: return true
        case .senseVoice, .parakeetSherpa, .qwen3MLX06B, .qwen3MLX17B: return false
        }
    }

    static func fromMenuTag(_ tag: Int) -> ASRBackend {
        Self.allCases.first { $0.menuTag == tag } ?? .senseVoice
    }

    static func fromMenuValue(_ value: String?) -> ASRBackend {
        guard let value, let backend = ASRBackend(rawValue: value) else {
            return .senseVoice
        }
        return backend
    }
}

struct ASRConfiguration {
    let languageMode: RecognitionLanguageMode
    let backend: ASRBackend

    static func current() -> ASRConfiguration {
        ASRConfiguration(languageMode: .load(), backend: .load())
    }
}

struct RecordingTask {
    let id: UUID
    let audioURL: URL
    let targetApp: NSRunningApplication?
    let configuration: ASRConfiguration
    let purpose: SpeechInputPurpose
    let duration: TimeInterval
    let finishRequestedAt: Date
    /// 从 SpeechSession 继承的本次录音收尾策略，禁止在停止后重新读取 UI。
    let reRecognizeWholeRecordingAfterStop: Bool
    var realtimePreviewTextAtFinish: String = ""
}

struct RecentTranscription: Codable, Equatable {
    let text: String
    let recognitionSeconds: Double?
    let sourceText: String?
    let translatedText: String?
    let translationDirection: SmartTranslationDirection?
    let usage: SmartUsage?

    init(
        text: String,
        recognitionSeconds: Double?,
        sourceText: String? = nil,
        translatedText: String? = nil,
        translationDirection: SmartTranslationDirection? = nil,
        usage: SmartUsage? = nil
    ) {
        self.text = text
        self.recognitionSeconds = recognitionSeconds
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.translationDirection = translationDirection
        self.usage = usage
    }

    var hasTranslation: Bool {
        guard let sourceText, let translatedText else { return false }
        return !sourceText.isEmpty && !translatedText.isEmpty
    }

    var timeText: String {
        guard let recognitionSeconds else { return "识别时间 --" }
        return String(format: "识别时间 %.2f 秒", recognitionSeconds)
    }
}
