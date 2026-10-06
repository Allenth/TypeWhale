import Foundation

/// 识别结果进入 reducer/reconciler 前的统一短幻觉过滤。
/// 这里只判断“整次识别是否只是已知静音短语”，不改写正常句子。
struct RealtimeRecognitionHallucinationFilter: Sendable {
    enum Authority: String, Equatable, Sendable {
        case fast
        case correction
        case stopTail
    }

    enum Reason: String, Equatable, Sendable {
        case silencePhrase
        case latinSilencePhrase
        case punctuationNoise
    }

    enum Decision: Equatable, Sendable {
        case keep(String)
        case suppress(reason: Reason)
    }

    private let silencePhrases: Set<String> = [
        "我", "嗯", "啊", "呃", "额", "哦", "唔", "呣", "诶", "哎", "呐", "嗯嗯", "啊啊",
        "我想", "谢谢", "谢谢大家", "谢谢观看", "谢谢观赏", "请", "请观看", "字幕", "中文字幕", "字幕志愿者",
    ]
    private let latinSilencePhrases: Set<String> = [
        "yeah", "yeahthe", "the", "you", "thankyou", "thankyouverymuch", "thanks",
        "thanksforwatching", "bye", "byebye", "okay", "ok", "uh", "um", "umm",
        "mm", "mmm", "hmm", "uhhuh", "huh", "so", "oh", "hi", "hey", "well",
        "please", "subscribe", "and", "amen", "iknow", "i",
    ]
    func evaluate(
        text: String,
        previousPreviewText _: String,
        authority _: Authority
    ) -> Decision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let semantic = semanticText(trimmed)
        guard !semantic.isEmpty else {
            return .suppress(reason: .punctuationNoise)
        }
        if silencePhrases.contains(semantic) {
            return .suppress(reason: .silencePhrase)
        }
        if latinSilencePhrases.contains(semantic.lowercased()) {
            return .suppress(reason: .latinSilencePhrase)
        }
        return .keep(trimmed)
    }

    private func semanticText(_ text: String) -> String {
        text.unicodeScalars.compactMap { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) {
                return nil
            }
            return String(scalar)
        }.joined()
    }
}
