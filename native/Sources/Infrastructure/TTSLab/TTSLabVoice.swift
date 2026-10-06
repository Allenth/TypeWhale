import Foundation

enum TTSLabVoiceGroup: String, Codable, Equatable {
    case zipVoice
}

struct TTSLabVoice: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let group: TTSLabVoiceGroup
    let speakerID: Int?
    let isDefault: Bool

    var menuTitle: String {
        detail.isEmpty ? displayName : "\(displayName) · \(detail)"
    }
}

enum TTSLabVoiceCatalog {
    static let retainedModelID = "zipvoice-distill-int8-zh-en-emilia"
    static let fingerprintValue = "zipvoice-distill-int8-reference-voices-v2"

    static func candidates(for modelID: String) -> [TTSLabVoice] {
        modelID == retainedModelID ? zipVoiceVoices : []
    }

    static func fingerprint(for modelID: String) -> String? {
        modelID == retainedModelID ? fingerprintValue : nil
    }

    static func availableVoices(
        qualifiedVoiceIDs: Set<String>,
        personalVoice: TTSLabVoice?
    ) -> [TTSLabVoice] {
        var voices = candidates(for: retainedModelID).filter {
            qualifiedVoiceIDs.contains($0.id)
        }
        if let personalVoice {
            voices.append(personalVoice)
        }
        return voices
    }

    private static let zipVoiceVoices: [TTSLabVoice] = [
        TTSLabVoice(
            id: "zipvoice-default",
            displayName: "默认新闻女声",
            detail: "原始参考 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: true
        ),
        TTSLabVoice(
            id: "zipvoice-serena",
            displayName: "Serena 克隆",
            detail: "Qwen 0.6B 来源 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: false
        ),
        TTSLabVoice(
            id: "zipvoice-cosy",
            displayName: "CosyVoice 克隆",
            detail: "CosyVoice 来源 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: false
        ),
        TTSLabVoice(
            id: "zipvoice-video-reference",
            displayName: "视频参考音色",
            detail: "用户本地样本 · 实验",
            group: .zipVoice,
            speakerID: nil,
            isDefault: false
        ),
    ]
}
