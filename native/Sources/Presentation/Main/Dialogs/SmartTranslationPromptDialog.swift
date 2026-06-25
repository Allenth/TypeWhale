import AppKit

final class SmartTranslationPromptDialog: NSObject {
    enum Result {
        case save(SmartTranslationDirection, String)
        case reset(SmartTranslationDirection)
        case cancel
    }

    private let directionPicker = NSPopUpButton()
    private let textView = NSTextView()
    private var selectedDirection: SmartTranslationDirection

    init(initialDirection: SmartTranslationDirection) {
        selectedDirection = initialDirection
        super.init()
    }

    func runModal() -> Result {
        let alert = NSAlert()
        alert.messageText = "翻译提示词"
        alert.informativeText = "选择翻译方向，修改语气和表达规则后保存。中译英提示词会影响英文翻译的口语化风格。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = buildAccessoryView()
        loadTemplate(for: selectedDirection)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(selectedDirection, textView.string)
        case .alertSecondButtonReturn:
            return .reset(selectedDirection)
        default:
            return .cancel
        }
    }

    private func buildAccessoryView() -> NSView {
        directionPicker.removeAllItems()
        for direction in SmartTranslationDirection.allCases {
            directionPicker.addItem(withTitle: direction.displayName)
            directionPicker.lastItem?.representedObject = direction.rawValue
        }
        directionPicker.selectItem(withTitle: selectedDirection.displayName)
        directionPicker.target = self
        directionPicker.action = #selector(directionDidChange)
        directionPicker.bezelStyle = .rounded
        directionPicker.controlSize = .regular

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
        textView.frame = NSRect(x: 0, y: 0, width: 460, height: 260)
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

        let hint = NSTextField(labelWithString: "保存空内容会恢复默认。这里只写翻译语气和表达规则，原文会由 TypeWhale 自动附加。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [directionPicker, scrollView, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            directionPicker.widthAnchor.constraint(equalToConstant: 160),
            scrollView.widthAnchor.constraint(equalToConstant: 460),
            scrollView.heightAnchor.constraint(equalToConstant: 260),
            hint.widthAnchor.constraint(equalToConstant: 460),
        ])
        return container
    }

    @objc private func directionDidChange() {
        guard let rawValue = directionPicker.selectedItem?.representedObject as? String,
              let direction = SmartTranslationDirection(rawValue: rawValue) else {
            return
        }
        selectedDirection = direction
        loadTemplate(for: direction)
    }

    private func loadTemplate(for direction: SmartTranslationDirection) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: SmartTranslationPromptStore.template(for: direction),
            attributes: attributes
        ))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}

