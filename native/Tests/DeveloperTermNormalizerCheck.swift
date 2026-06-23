import Foundation

@main
struct DeveloperTermNormalizerCheck {
    static func main() {
        let normalizer = DeveloperTermNormalizer(termsProvider: { DeveloperLexiconStore.defaultTerms })
        let context = SmartInputContext(targetAppName: "Codex", targetBundleIdentifier: "com.openai.codex")

        assert(
            normalizer.normalize("让扣德克斯帮我整理开发需求", context: context).text,
            equals: "让 Codex 帮我整理开发需求"
        )
        assert(
            normalizer.normalize("比较一下 q wen asr 和 sense voice", context: context).text,
            equals: "比较一下 Qwen3-ASR 和 SenseVoice"
        )
        assert(
            normalizer.normalize("我想优化 recording capsule view 的实时预览", context: context).text,
            equals: "我想优化 RecordingCapsuleView 的实时预览"
        )
        assert(
            normalizer.normalize("这个 code 要重新写", context: context).text,
            equals: "这个 code 要重新写"
        )
        assert(
            normalizer.normalize("帮我看一下 claude code 和 cursor 哪个适合", context: context).text,
            equals: "帮我看一下 Claude Code 和 Cursor 哪个适合"
        )
        assert(
            normalizer.normalize("这个 oppoingpo 适合写知识库吗", context: context).text,
            equals: "这个 Obsidian 适合写知识库吗"
        )
        assert(
            normalizer.normalize("我想把内容保存到欧布西迪安里面", context: context).text,
            equals: "我想把内容保存到 Obsidian 里面"
        )

        let secure = normalizer.normalize(
            "让扣德克斯帮我整理开发需求",
            context: SmartInputContext(targetAppName: "Any", targetBundleIdentifier: nil, isSecureTextEntry: true)
        )
        assert(secure.text, equals: "让扣德克斯帮我整理开发需求")
        precondition(secure.replacements.isEmpty)
    }

    private static func assert(_ actual: String, equals expected: String) {
        precondition(actual == expected, "Expected [\(expected)], got [\(actual)]")
    }
}
