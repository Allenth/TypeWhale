import Foundation

enum DeveloperLexiconStore {
    private static let storageKey = "developerLexicon.terms.v1"

    static func load() -> [DeveloperTerm] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let terms = try? JSONDecoder().decode([DeveloperTerm].self, from: data),
              !terms.isEmpty else {
            return defaultTerms
        }
        return mergeStoredTermsWithDefaults(terms)
    }

    static func save(_ terms: [DeveloperTerm]) {
        let cleaned = terms
            .map(clean)
            .filter { !$0.canonical.isEmpty }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static var promptGlossary: String {
        promptGlossary(for: load())
    }

    static func promptGlossary(matching text: String, maxTerms: Int = 8) -> String? {
        let relevantTerms = relevantTerms(in: text, maxTerms: maxTerms)
        guard !relevantTerms.isEmpty else { return nil }
        return promptGlossary(for: relevantTerms)
    }

    static func promptGlossary(for terms: [DeveloperTerm]) -> String {
        let lines = terms
            .sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
            .map { term -> String in
                let aliases = term.aliases.prefix(6).joined(separator: ", ")
                return "- \(term.canonical): \(term.category.displayName). Aliases: \(aliases)"
            }
        return lines.joined(separator: "\n")
    }

    private static func relevantTerms(in text: String, maxTerms: Int) -> [DeveloperTerm] {
        let haystack = comparable(text)
        guard !haystack.isEmpty else { return [] }

        var matches: [(term: DeveloperTerm, score: Int)] = []
        for term in load() {
            let candidates = [term.canonical] + term.aliases
            let score = candidates.compactMap { candidate -> Int? in
                let needle = comparable(candidate)
                guard needle.count >= 2, haystack.contains(needle) else { return nil }
                return needle.count
            }.max()
            if let score {
                matches.append((term, score))
            }
        }

        return matches
            .sorted {
                if $0.score == $1.score {
                    return $0.term.canonical.localizedCaseInsensitiveCompare($1.term.canonical) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(maxTerms)
            .map(\.term)
    }

    private static func comparable(_ value: String) -> String {
        value
            .filter { $0.isLetter || $0.isNumber || isChinese($0) }
            .lowercased()
    }

    private static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func clean(_ term: DeveloperTerm) -> DeveloperTerm {
        DeveloperTerm(
            id: term.id,
            canonical: term.canonical.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: uniqueAliases(term.aliases),
            category: term.category,
            caseSensitive: term.caseSensitive
        )
    }

    private static func uniqueAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { alias in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private static func mergeStoredTermsWithDefaults(_ stored: [DeveloperTerm]) -> [DeveloperTerm] {
        let defaultsByCanonical = Dictionary(
            uniqueKeysWithValues: defaultTerms.map { ($0.canonical.lowercased(), clean($0)) }
        )
        var merged = stored.map { storedTerm in
            let cleaned = clean(storedTerm)
            guard let defaultTerm = defaultsByCanonical[cleaned.canonical.lowercased()] else {
                return cleaned
            }
            return DeveloperTerm(
                id: cleaned.id,
                canonical: cleaned.canonical,
                aliases: uniqueAliases(cleaned.aliases + defaultTerm.aliases),
                category: cleaned.category,
                caseSensitive: cleaned.caseSensitive
            )
        }
        let existing = Set(merged.map { $0.canonical.lowercased() })
        let missingDefaults = defaultTerms.filter { !existing.contains($0.canonical.lowercased()) }
        merged.append(contentsOf: missingDefaults)
        return merged
    }

    static let defaultTerms: [DeveloperTerm] = [
        DeveloperTerm(canonical: "Codex", aliases: ["code x", "codex", "扣德克斯", "寇德克斯", "Cordex"], category: .tool),
        DeveloperTerm(canonical: "Claude Code", aliases: ["claude code", "克劳德 code", "克劳德扣的", "Claude Coder"], category: .tool),
        DeveloperTerm(canonical: "Cursor", aliases: ["cursor", "柯索", "光标编辑器"], category: .tool),
        DeveloperTerm(canonical: "ChatGPT", aliases: ["chat gpt", "chatgpt", "GPT", "gpt"], category: .tool),
        DeveloperTerm(canonical: "GitHub", aliases: ["github", "git hub"], category: .tool),
        DeveloperTerm(canonical: "Git", aliases: ["git"], category: .tool),
        DeveloperTerm(canonical: "Obsidian", aliases: ["obsidian", "obsidian 笔记", "obsidian note", "oseing", "oosing", "oing", "osing", "oppoingpo", "obpoing", "obpoingpo", "oppoing", "欧布西迪安", "欧布西迪安笔记", "黑曜石", "黑曜石笔记"], category: .tool),
        DeveloperTerm(canonical: "Qwen", aliases: ["qwen", "千问", "通义千问"], category: .model),
        DeveloperTerm(canonical: "Qwen3-ASR", aliases: ["qwen3 asr", "qwen asr", "q wen asr", "千问 asr", "Qwen ASR", "Qwen3 ASR"], category: .model),
        DeveloperTerm(canonical: "SenseVoice", aliases: ["sense voice", "sensevoice", "森斯 voice"], category: .model),
        DeveloperTerm(canonical: "Whisper", aliases: ["whisper", "openai whisper"], category: .model),
        DeveloperTerm(canonical: "Parakeet", aliases: ["parakeet"], category: .model),
        DeveloperTerm(canonical: "sherpa-onnx", aliases: ["sherpa onnx", "sherpa-onnx", "雪巴 onnx"], category: .model),
        DeveloperTerm(canonical: "Vosk", aliases: ["vosk"], category: .model),
        DeveloperTerm(canonical: "macOS", aliases: ["mac os", "macos", "麦克 os"], category: .product),
        DeveloperTerm(canonical: "Apple Silicon", aliases: ["apple silicon", "苹果 silicon", "m 系列芯片"], category: .product),
        DeveloperTerm(canonical: "Swift", aliases: ["swift"], category: .language),
        DeveloperTerm(canonical: "SwiftUI", aliases: ["swift ui", "swiftui"], category: .framework),
        DeveloperTerm(canonical: "AppKit", aliases: ["app kit", "appkit"], category: .framework),
        DeveloperTerm(canonical: "Xcode", aliases: ["xcode", "x code"], category: .tool),
        DeveloperTerm(canonical: "ASR", aliases: ["asr", "a s r", "语音识别模型"], category: .acronym),
        DeveloperTerm(canonical: "LLM", aliases: ["llm", "l l m", "大语言模型"], category: .acronym),
        DeveloperTerm(canonical: "API", aliases: ["api", "a p i"], category: .api),
        DeveloperTerm(canonical: "SDK", aliases: ["sdk", "s d k"], category: .api),
        DeveloperTerm(canonical: "CLI", aliases: ["cli", "c l i"], category: .api),
        DeveloperTerm(canonical: "UI", aliases: ["ui", "u i"], category: .acronym),
        DeveloperTerm(canonical: "UX", aliases: ["ux", "u x"], category: .acronym),
        DeveloperTerm(canonical: "JSON", aliases: ["json", "j son", "jason", "杰森"], category: .api),
        DeveloperTerm(canonical: "JSON 格式", aliases: ["json 格式", "j son 格式", "jason 格式", "杰森格式", "JSON format"], category: .api),
        DeveloperTerm(canonical: "Markdown", aliases: ["markdown", "mark down"], category: .api),
        DeveloperTerm(canonical: "Node.js", aliases: ["node js", "node.js", "node"], category: .language),
        DeveloperTerm(canonical: "Python", aliases: ["python", "派森"], category: .language),
        DeveloperTerm(canonical: "Electron", aliases: ["electron"], category: .framework),
        DeveloperTerm(canonical: "TypeWhale", aliases: ["type whale", "typewhale", "泰普 whale"], category: .project),
        DeveloperTerm(canonical: "TypeSpeaker", aliases: ["type speaker", "typespeaker"], category: .project),
        DeveloperTerm(canonical: "RecordingCapsuleView", aliases: ["recording capsule view", "recordingcapsuleview"], category: .project),
        DeveloperTerm(canonical: "TranscriptDiffStabilizer", aliases: ["transcript diff stabilizer", "transcriptdiffstabilizer"], category: .project),
        DeveloperTerm(canonical: "SmartRewriteEngine", aliases: ["smart rewrite engine", "smartrewriteengine"], category: .project),
    ]
}
