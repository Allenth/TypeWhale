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
            caseSensitive: term.caseSensitive,
            allowsFuzzy: term.allowsFuzzy
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
                caseSensitive: cleaned.caseSensitive,
                allowsFuzzy: cleaned.allowsFuzzy || defaultTerm.allowsFuzzy
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
        DeveloperTerm(canonical: "Ollama", aliases: ["ollama", "alama", "alma", "奥拉马", "奥拉玛", "欧拉马", "欧拉玛", "拉马"], category: .tool, allowsFuzzy: true),
        DeveloperTerm(canonical: "DeepSeek", aliases: ["deepseek", "deep seek", "迪普西克", "深度求索"], category: .model),
        DeveloperTerm(canonical: "DeepSeek v4 flash", aliases: ["deepseek v4 flash", "deep seek v4 flash", "deepseek-v4-flash", "迪普西克 v4 flash", "深度求索 v4 flash"], category: .model),
        DeveloperTerm(canonical: "MiniMax", aliases: ["minimax", "mini max", "迷你麦克斯", "迷你 max"], category: .model),
        DeveloperTerm(canonical: "MiniMax M2", aliases: ["minimax m2", "mini max m2", "迷你麦克斯 m2", "迷你 max m2"], category: .model),
        DeveloperTerm(canonical: "Qwen", aliases: ["qwen", "千问", "通义千问"], category: .model),
        DeveloperTerm(canonical: "Qwen3-ASR", aliases: ["qwen3 asr", "qwen asr", "q wen asr", "千问 asr", "Qwen ASR", "Qwen3 ASR"], category: .model),
        DeveloperTerm(canonical: "Qwen3.6", aliases: ["qwen3.6", "qwen 3.6", "q wen 3.6", "qwen 三点六", "q wen 三点六", "千问 3.6", "千问三点六"], category: .model),
        DeveloperTerm(canonical: "Qwen3.6 8B", aliases: ["qwen3.6 8b", "qwen 3.6 8b", "q wen 3.6 8b", "qwen 三点六 8b", "q wen 三点六 八 b", "千问三点六 8b"], category: .model),
        DeveloperTerm(canonical: "Qwen3.6 35B", aliases: ["qwen3.6 35b", "qwen 3.6 35b", "q wen 3.6 35b", "qwen 3.635b", "q wen 3.635b", "qwen 三点六 35b", "q wen 三点六 三十五 b", "千问三点六 35b", "纤问 3.635b", "纤温 3.635b", "千问 3.635b"], category: .model),
        DeveloperTerm(canonical: "SenseVoice", aliases: ["sense voice", "sensevoice", "森斯 voice"], category: .model),
        DeveloperTerm(canonical: "Whisper", aliases: ["whisper", "openai whisper"], category: .model),
        DeveloperTerm(canonical: "Parakeet", aliases: ["parakeet"], category: .model),
        DeveloperTerm(canonical: "sherpa-onnx", aliases: ["sherpa onnx", "sherpa-onnx", "雪巴 onnx"], category: .model),
        DeveloperTerm(canonical: "Vosk", aliases: ["vosk"], category: .model),
        DeveloperTerm(canonical: "ONNX Runtime", aliases: ["onnx runtime", "onnxruntime", "on x runtime"], category: .framework),
        DeveloperTerm(canonical: "MLX", aliases: ["mlx", "m l x"], category: .framework),
        DeveloperTerm(canonical: "macOS", aliases: ["mac os", "macos", "麦克 os"], category: .product),
        DeveloperTerm(canonical: "Apple Silicon", aliases: ["apple silicon", "苹果 silicon", "m 系列芯片"], category: .product),
        DeveloperTerm(canonical: "Swift", aliases: ["swift"], category: .language),
        DeveloperTerm(canonical: "SwiftUI", aliases: ["swift ui", "swiftui"], category: .framework),
        DeveloperTerm(canonical: "AppKit", aliases: ["app kit", "appkit"], category: .framework),
        DeveloperTerm(canonical: "ScreenCaptureKit", aliases: ["screen capture kit", "screencapturekit"], category: .framework, allowsFuzzy: true),
        DeveloperTerm(canonical: "WebView", aliases: ["web view", "webview"], category: .framework),
        DeveloperTerm(canonical: "WKWebView", aliases: ["wk web view", "wkwebview"], category: .framework),
        DeveloperTerm(canonical: "Keychain", aliases: ["keychain", "key chain", "钥匙串"], category: .framework),
        DeveloperTerm(canonical: "UserDefaults", aliases: ["user defaults", "userdefaults"], category: .framework),
        DeveloperTerm(canonical: "Info.plist", aliases: ["info plist", "info.plist"], category: .framework),
        DeveloperTerm(canonical: "CFBundleVersion", aliases: ["cf bundle version", "cfbundleversion"], category: .framework),
        DeveloperTerm(canonical: "CFBundleShortVersionString", aliases: ["cf bundle short version string", "cfbundleshortversionstring"], category: .framework),
        DeveloperTerm(canonical: "NSAlert", aliases: ["ns alert", "nsalert"], category: .framework),
        DeveloperTerm(canonical: "NSPanel", aliases: ["ns panel", "nspanel"], category: .framework),
        DeveloperTerm(canonical: "NSWindow", aliases: ["ns window", "nswindow"], category: .framework),
        DeveloperTerm(canonical: "NSTextView", aliases: ["ns text view", "nstextview"], category: .framework),
        DeveloperTerm(canonical: "NSPopUpButton", aliases: ["ns popup button", "ns pop up button", "nspopupbutton"], category: .framework),
        DeveloperTerm(canonical: "NSButton", aliases: ["ns button", "nsbutton"], category: .framework),
        DeveloperTerm(canonical: "NSView", aliases: ["ns view", "nsview"], category: .framework),
        DeveloperTerm(canonical: "NSVisualEffectView", aliases: ["ns visual effect view", "nsvisualeffectview"], category: .framework),
        DeveloperTerm(canonical: "NSBezierPath", aliases: ["ns bezier path", "nsbezierpath"], category: .framework),
        DeveloperTerm(canonical: "CoreGraphics", aliases: ["core graphics", "coregraphics"], category: .framework),
        DeveloperTerm(canonical: "QuartzCore", aliases: ["quartz core", "quartzcore"], category: .framework),
        DeveloperTerm(canonical: "Vision OCR", aliases: ["vision ocr", "vision optical character recognition"], category: .framework),
        DeveloperTerm(canonical: "XPC", aliases: ["xpc", "x p c"], category: .framework),
        DeveloperTerm(canonical: "Xcode", aliases: ["xcode", "x code"], category: .tool),
        DeveloperTerm(canonical: "ASR", aliases: ["asr", "a s r", "语音识别模型"], category: .acronym),
        DeveloperTerm(canonical: "VAD", aliases: ["vad", "v a d", "语音活动检测"], category: .acronym),
        DeveloperTerm(canonical: "OCR", aliases: ["ocr", "o c r", "文字识别"], category: .acronym),
        DeveloperTerm(canonical: "AX", aliases: ["ax", "accessibility api", "accessibility"], category: .acronym),
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
        DeveloperTerm(canonical: "用 Ollama 检查 Qwen3.6 35B", aliases: ["使用 check full question 3.635b"], category: .project),
        DeveloperTerm(canonical: "Ollama 检查 Qwen3.6 35B", aliases: ["check full question 3.635b"], category: .project),
        DeveloperTerm(canonical: "RecordingCapsuleView", aliases: ["recording capsule view", "recordingcapsuleview"], category: .project),
        DeveloperTerm(canonical: "SpeechInputCoordinator", aliases: ["speech input coordinator", "speechinputcoordinator"], category: .project),
        DeveloperTerm(canonical: "SmartInputRouter", aliases: ["smart input router", "smartinputrouter"], category: .project),
        DeveloperTerm(canonical: "SmartRewritePromptBuilder", aliases: ["smart rewrite prompt builder", "smartrewritepromptbuilder"], category: .project),
        DeveloperTerm(canonical: "DeveloperTermNormalizer", aliases: ["developer term normalizer", "developertermnormalizer"], category: .project),
        DeveloperTerm(canonical: "DeveloperLexiconStore", aliases: ["developer lexicon store", "developerlexiconstore"], category: .project),
        DeveloperTerm(canonical: "TranscriptDiffStabilizer", aliases: ["transcript diff stabilizer", "transcriptdiffstabilizer"], category: .project),
        DeveloperTerm(canonical: "SmartRewriteEngine", aliases: ["smart rewrite engine", "smartrewriteengine"], category: .project),
    ]
}
