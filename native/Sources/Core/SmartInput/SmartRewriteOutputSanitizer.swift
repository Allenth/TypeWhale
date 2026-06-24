import Foundation

enum SmartRewriteOutputSanitizer {
    static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lines = trimmed.components(separatedBy: .newlines)
        if let markerIndex = lines.lastIndex(where: isRewriteMarker),
           markerIndex < lines.index(before: lines.endIndex) {
            let tail = lines[lines.index(after: markerIndex)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                return tail
            }
        }

        let kept = lines.drop(while: isMetaExplanationLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? trimmed : kept
    }

    private static func isRewriteMarker(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "整理后如下：" ||
            normalized == "整理后如下:" ||
            normalized == "整理如下：" ||
            normalized == "整理如下:"
    }

    private static func isMetaExplanationLine(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let patterns = [
            "原始语音文本是",
            "根据规则",
            "按照规则",
            "我不能执行",
            "不能执行这个指令",
            "只能整理文本本身",
            "只会整理文本本身",
            "整理后如下",
        ]
        return patterns.contains { normalized.contains($0) }
    }
}
