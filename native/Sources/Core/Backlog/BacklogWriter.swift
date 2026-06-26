import Foundation

struct BacklogSaveContext {
    let rawText: String
    let finalText: String
    let modeName: String
    let targetAppName: String?
    let recordingSessionID: UUID
}

enum BacklogWriter {
    static func shouldSave(rawText: String) -> Bool {
        let text = normalized(rawText)
        return saveIntentTokens.contains { text.contains($0) }
    }

    static func save(_ context: BacklogSaveContext, directory: URL = BacklogDirectoryStore.directory) throws -> URL {
        let directoryURL = BacklogDirectoryStore.ensureDirectory(directory)
        let title = titleText(from: context.finalText, fallback: context.rawText)
        let fileURL = uniqueFileURL(in: directoryURL, title: title)
        let body = markdown(context: context, title: title)
        try body.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func markdown(context: BacklogSaveContext, title: String) -> String {
        let createdAt = isoFormatter.string(from: Date())
        let cleanFinal = cleanedContent(context.finalText)
        let cleanRaw = cleanedContent(context.rawText)
        let target = context.targetAppName ?? "未知"
        return """
        ---
        type: backlog
        created_at: \(createdAt)
        source: TypeWhale
        recording_session_id: \(context.recordingSessionID.uuidString)
        mode: \(escapeYAML(context.modeName))
        target_app: \(escapeYAML(target))
        ---

        # \(title)

        ## 需求描述

        \(cleanFinal.isEmpty ? cleanRaw : cleanFinal)

        ## 原始语音

        \(cleanRaw)

        ## 验收要点

        - [ ] 待拆解

        """
    }

    private static func titleText(from finalText: String, fallback rawText: String) -> String {
        let source = cleanedContent(finalText).isEmpty ? cleanedContent(rawText) : cleanedContent(finalText)
        let firstLine = source
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Backlog 需求"
        let stripped = firstLine
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(36)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Backlog 需求"
            : String(stripped.prefix(36)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedContent(_ text: String) -> String {
        var result = text
        cleanupPatterns.forEach {
            result = result.replacingOccurrences(of: $0, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueFileURL(in directory: URL, title: String) -> URL {
        let timestamp = fileFormatter.string(from: Date())
        let slug = sanitizedFileName(title)
        let baseName = "\(timestamp)-\(slug.isEmpty ? "backlog" : slug)"
        var candidate = directory.appendingPathComponent("\(baseName).md")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).md")
            index += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|#[]{}")
        let parts = text.components(separatedBy: invalid).joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: "-")
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private static let saveIntentTokens = [
        "backlog",
        "需求池",
        "存入需求",
        "存到需求",
        "保存需求",
        "记录需求",
        "加入需求",
        "存成需求",
        "整理成需求",
        "写成需求"
    ]

    private static let cleanupPatterns = [
        "(?i)存入\\s*backlog",
        "(?i)存到\\s*backlog",
        "(?i)加入\\s*backlog",
        "(?i)保存\\s*backlog",
        "(?i)记录\\s*backlog",
        "(?i)backlog",
        "存入\\s*需求池",
        "存到\\s*需求池",
        "保存到\\s*需求池",
        "保存\\s*需求",
        "记录\\s*需求",
        "加入\\s*需求池",
        "放进\\s*需求池",
        "放到\\s*需求池",
        "写入\\s*需求池",
        "存成\\s*需求",
        "整理成\\s*需求",
        "写成\\s*需求"
    ]

    private static func escapeYAML(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
