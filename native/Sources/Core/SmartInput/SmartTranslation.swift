import Foundation

enum SmartTranslationDirection: String, CaseIterable, Codable {
    case chineseToEnglish
    case englishToChinese

    var displayName: String {
        switch self {
        case .chineseToEnglish: return "中译英"
        case .englishToChinese: return "英译中"
        }
    }

    var sourceLabel: String {
        switch self {
        case .chineseToEnglish: return "中文原文"
        case .englishToChinese: return "English source"
        }
    }

    var targetLabel: String {
        switch self {
        case .chineseToEnglish: return "English"
        case .englishToChinese: return "中文译文"
        }
    }

    var targetLanguageInstruction: String {
        switch self {
        case .chineseToEnglish:
            return "把原始语音文本翻译成自然、清晰、适合直接粘贴的英文。"
        case .englishToChinese:
            return "把原始语音文本翻译成自然、清晰、适合直接粘贴的中文。"
        }
    }

    var usesRawSourceTextForTranslation: Bool {
        switch self {
        case .chineseToEnglish:
            return true
        case .englishToChinese:
            return false
        }
    }

    var toneInstruction: String {
        SmartTranslationPromptStore.template(for: self)
    }

    var menuTag: Int {
        switch self {
        case .chineseToEnglish: return 0
        case .englishToChinese: return 1
        }
    }

    static func fromMenuTag(_ tag: Int) -> SmartTranslationDirection {
        Self.allCases.first { $0.menuTag == tag } ?? .chineseToEnglish
    }
}

struct SmartTranslationOutput {
    let sourceText: String
    let translatedText: String
    let direction: SmartTranslationDirection
    let modelName: String
    let usage: SmartUsage?
}
