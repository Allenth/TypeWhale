import Foundation

enum ASRBackend: String {
    case automatic
}

enum SmartRewritePreference: String {
    case automatic
    case raw
    case polish
    case developerRequirement
    case exhaustiveSummary
}

enum SmartTranslationDirection: String {
    case chineseToEnglish
}

struct AudioInputDevice {
    static let systemDefaultUID = ""
    static let selectionStorageKey = "audioInputDeviceUID"
}

@main
struct IdeaPillWriterCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-idea-pill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixedDate = Date(timeIntervalSince1970: 1_783_213_680)
        let context = BacklogSaveContext(
            rawText: "我刚想到一个 AI 胶囊自动归档的想法。",
            finalText: """
            # AI 胶囊自动归档

            把闪念胶囊里的整理结果自动保存成 Obsidian 笔记。
            """,
            modeName: "自动",
            targetAppName: "Codex",
            recordingSessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )

        let firstURL = try BacklogWriter.saveIdeaPill(context, rootDirectory: root, now: fixedDate)
        precondition(firstURL.deletingLastPathComponent().lastPathComponent == "闪念胶囊")
        precondition(firstURL.lastPathComponent == "260705-0908-AI-胶囊自动归档-idea-pill.md")

        let firstContent = try String(contentsOf: firstURL, encoding: .utf8)
        precondition(firstContent.contains("type: idea_pill"))
        precondition(firstContent.contains("source: TypeWhale"))
        precondition(firstContent.contains("mode: \"自动\""))
        precondition(firstContent.contains("target_app: \"Codex\""))
        precondition(firstContent.contains("# AI 胶囊自动归档"))
        precondition(firstContent.contains("把闪念胶囊里的整理结果自动保存成 Obsidian 笔记。"))
        precondition(firstContent.contains("## 原始语音"))
        precondition(firstContent.contains("我刚想到一个 AI 胶囊自动归档的想法。"))

        let secondURL = try BacklogWriter.saveIdeaPill(context, rootDirectory: root, now: fixedDate)
        precondition(secondURL.lastPathComponent == "260705-0908-AI-胶囊自动归档-idea-pill-2.md")

        let archiveContext = BacklogSaveContext(
            rawText: context.rawText,
            finalText: context.finalText,
            modeName: "极致归纳",
            targetAppName: "知识点",
            recordingSessionID: context.recordingSessionID
        )
        let archiveURL = try BacklogWriter.saveKnowledgeArchive(archiveContext, rootDirectory: root, now: fixedDate)
        precondition(archiveURL.deletingLastPathComponent().lastPathComponent == "2026-07-05")
        precondition(archiveURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "归档（未处理）")
        precondition(archiveURL.lastPathComponent == "归档-260705-0908-AI-胶囊自动归档.md")

        let sameDayArchiveURL = try BacklogWriter.saveKnowledgeArchive(
            archiveContext,
            rootDirectory: root,
            now: fixedDate.addingTimeInterval(60 * 30)
        )
        precondition(sameDayArchiveURL.deletingLastPathComponent().path == archiveURL.deletingLastPathComponent().path)

        let nextDayArchiveURL = try BacklogWriter.saveKnowledgeArchive(
            archiveContext,
            rootDirectory: root,
            now: fixedDate.addingTimeInterval(60 * 60 * 24)
        )
        precondition(nextDayArchiveURL.deletingLastPathComponent().lastPathComponent == "2026-07-06")
        precondition(nextDayArchiveURL.deletingLastPathComponent().path != archiveURL.deletingLastPathComponent().path)

        let archiveContent = try String(contentsOf: archiveURL, encoding: .utf8)
        precondition(archiveContent.contains("type: knowledge_archive"))
        precondition(archiveContent.contains("source: TypeWhale Screenshot Archive"))
        precondition(archiveContent.contains("mode: \"极致归纳\""))
        precondition(archiveContent.contains("target_app: \"知识点\""))
        precondition(archiveContent.contains("# AI 胶囊自动归档"))
        precondition(archiveContent.contains("## 知识点"))
        precondition(archiveContent.contains("把闪念胶囊里的整理结果自动保存成 Obsidian 笔记。"))
        precondition(archiveContent.contains("## OCR 原文"))

        print("IdeaPillWriterCheck passed")
    }
}
