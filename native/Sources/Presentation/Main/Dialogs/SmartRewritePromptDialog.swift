import AppKit

final class SmartRewritePromptDialog: NSObject {
    enum Result {
        case save(RewriteMode, String)
        case reset(RewriteMode)
        case cancel
    }

    private let modePicker = NSPopUpButton()
    private let textView = NSTextView()
    private var selectedMode: RewriteMode

    init(initialMode: RewriteMode) {
        selectedMode = SmartRewritePromptStore.editableModes.contains(initialMode) ? initialMode : .developerRequirement
        super.init()
    }

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "智能整理提示词"
        alert.informativeText = "选择一种整理模式，修改提示词后保存。可用占位符：{rawText}、{targetAppName}、{targetBundleIdentifier}。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTemplate(for: selectedMode)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(selectedMode, textView.string)
        case .alertSecondButtonReturn:
            return .reset(selectedMode)
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        modePicker.removeAllItems()
        for mode in SmartRewritePromptStore.editableModes {
            modePicker.addItem(withTitle: mode.displayName)
            modePicker.lastItem?.representedObject = mode.rawValue
        }
        modePicker.selectItem(withTitle: selectedMode.displayName)
        modePicker.target = self
        modePicker.action = #selector(modeDidChange)
        modePicker.bezelStyle = .rounded
        modePicker.controlSize = .regular

        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        textView.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedWhite: 1, alpha: 1)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 460, height: 300)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "保存空内容会恢复默认。若忘记 {rawText}，TypeWhale 会自动补到模板末尾。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [modePicker, scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            modePicker.widthAnchor.constraint(equalToConstant: 160),
            scrollView.widthAnchor.constraint(equalToConstant: 460),
            scrollView.heightAnchor.constraint(equalToConstant: 300),
            hint.widthAnchor.constraint(equalToConstant: 460),
        ])
        return container
    }

    @objc private func modeDidChange() {
        guard let rawValue = modePicker.selectedItem?.representedObject as? String,
              let mode = RewriteMode(rawValue: rawValue) else {
            return
        }
        selectedMode = mode
        loadTemplate(for: mode)
    }

    private func loadTemplate(for mode: RewriteMode) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: SmartRewritePromptStore.template(for: mode),
            attributes: attributes
        ))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}

