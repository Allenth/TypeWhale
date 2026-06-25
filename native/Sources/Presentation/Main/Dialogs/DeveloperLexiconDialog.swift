import AppKit

final class DeveloperLexiconDialog: NSObject {
    enum Result {
        case save([DeveloperTerm])
        case reset
        case cancel
    }

    private let textView = NSTextView()

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "开发术语词库"
        alert.informativeText = "每行一个专业术语：标准词 | 分类 | 别名1, 别名2。新增一行即可添加词库，编辑或删除对应行即可管理现有术语。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTerms()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(parseTerms(from: textView.string))
        case .alertSecondButtonReturn:
            return .reset
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        textView.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedWhite: 1, alpha: 1)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "示例：OpenTelemetry | framework | open telemetry, otel。分类可用：tool、model、framework、language、api、product、project、acronym；无法识别的分类会按 project 保存。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 350))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 520),
            scrollView.heightAnchor.constraint(equalToConstant: 320),
            hint.widthAnchor.constraint(equalToConstant: 520),
        ])
        return container
    }

    private func loadTerms() {
        let text = DeveloperLexiconStore.load()
            .sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
            .map { term in
                "\(term.canonical) | \(term.category.rawValue) | \(term.aliases.joined(separator: ", "))"
            }
            .joined(separator: "\n")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func parseTerms(from text: String) -> [DeveloperTerm] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let canonical = parts.first, !canonical.isEmpty else { return nil }
            let category = parts.count > 1
                ? DeveloperTermCategory(rawValue: parts[1]) ?? .project
                : .project
            let aliases = parts.count > 2
                ? parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                : []
            return DeveloperTerm(canonical: canonical, aliases: aliases, category: category)
        }
    }
}
