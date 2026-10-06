import Foundation

@main
struct ASRHotwordEncoderCheck {
    static func main() throws {
        let words = [" 魔搭 ", "Qwen3-ASR", "魔搭", ""]
        let list = try ASRHotwordEncoder.encode(words: words, strategy: .nativeList)
        let spaced = try ASRHotwordEncoder.encode(words: words, strategy: .nativeSpaceSeparated)
        let sherpa = try ASRHotwordEncoder.encode(words: ["TypeWhale Pro"], strategy: .sherpaInline)
        let unsupported = try ASRHotwordEncoder.encode(words: ["Codex"], strategy: .unsupported)
        let context = try ASRHotwordEncoder.encode(words: ["Codex", "Obsidian"], strategy: .contextPrompt)
        precondition(list == .list(["魔搭", "Qwen3-ASR"]))
        precondition(spaced == .text("魔搭 Qwen3-ASR"))
        precondition(sherpa == .text("TypeWhale Pro"))
        precondition(unsupported == .none)
        precondition(context == .context("Codex, Obsidian"))

        let production = try ASRHotwordEncoder.encodeProduction(
            words: ["Codex", "Claude Code", "Qwen3-ASR"],
            strategy: .nativeSpaceSeparated
        )
        precondition(production.payload == .text("Codex Qwen3-ASR"))
        precondition(production.skippedWords == ["Claude Code"])

        let unsupportedProduction = try ASRHotwordEncoder.encodeProduction(
            words: ["Codex", "Claude Code"],
            strategy: .unsupported
        )
        precondition(unsupportedProduction.payload == .none)
        precondition(unsupportedProduction.skippedWords.isEmpty)

        do {
            _ = try ASRHotwordEncoder.encode(words: ["bad\nword"], strategy: .nativeList)
            preconditionFailure("newline must be rejected")
        } catch ASRHotwordEncodingError.invalidCharacters(let word) {
            precondition(word == "bad\nword")
        }

        do {
            _ = try ASRHotwordEncoder.encode(words: [String(repeating: "a", count: 257)], strategy: .nativeList)
            preconditionFailure("overlong word must be rejected")
        } catch ASRHotwordEncodingError.wordTooLong(let word) {
            precondition(word.count == 257)
        }

        do {
            _ = try ASRHotwordEncoder.encode(
                words: (0..<65).map { "word\($0)" },
                strategy: .nativeList
            )
            preconditionFailure("too many words must be rejected")
        } catch ASRHotwordEncodingError.tooManyWords(let count) {
            precondition(count == 65)
        }

        do {
            _ = try ASRHotwordEncoder.encode(
                words: ["TypeWhale Pro"],
                strategy: .nativeSpaceSeparated
            )
            preconditionFailure("space-separated providers cannot preserve a phrase containing spaces")
        } catch ASRHotwordEncodingError.phraseNotRepresentable(let word) {
            precondition(word == "TypeWhale Pro")
        }

        print("ASRHotwordEncoderCheck passed")
    }
}
