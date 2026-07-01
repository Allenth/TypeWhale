import AppKit

final class SocialScopeDialog: NSObject {
    enum Result {
        case save(String)
        case reset
        case cancel
    }

    private let textView = NSTextView()
    private let sheet = FormSheetController()

    func present(in parent: NSWindow, completion: @escaping (Result) -> Void) {
        let content = buildAccessoryView()
        loadList()
        sheet.present(
            in: parent,
            title: "社交应用清单",
            message: "每行一个关键词，小写后匹配目标 App 名 / Bundle ID / 窗口标题；命中即视为社交窗口，中译英改用“社交”提示词。# 开头的行为注释。",
            contentView: content,
            contentSize: NSSize(width: 460, height: 320),
            buttons: [
                .init(title: "保存", isDefault: true),
                .init(title: "恢复默认"),
                .init(title: "取消", isCancel: true),
            ]
        ) { [self] index in
            switch index {
            case 0:
                completion(.save(textView.string))
            case 1:
                completion(.reset)
            default:
                completion(.cancel)
            }
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

        let hint = NSTextField(labelWithString: "示例：微信、wechat、com.tencent、threads、x.com。保存空内容会恢复默认清单。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [scrollView, hint])
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
            scrollView.widthAnchor.constraint(equalToConstant: 460),
            scrollView.heightAnchor.constraint(equalToConstant: 260),
            hint.widthAnchor.constraint(equalToConstant: 460),
        ])
        return container
    }

    private func loadList() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: SmartTranslationSocialScopeStore.rawList(),
            attributes: attributes
        ))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
