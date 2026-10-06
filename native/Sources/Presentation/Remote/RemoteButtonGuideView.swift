import AppKit

@MainActor
final class RemoteButtonGuideView: NSView {
    private let illustrationView: RemoteControlIllustrationView
    private let recentButtonLabel = NSTextField(labelWithString: "")
    private var calloutViews: [RemoteButton: RemoteButtonCalloutView] = [:]
    private var usesCompactLayout = false
    private var currentMapping = RemoteButtonMapping.defaults
    private var lastRecognizedButton: RemoteButton?

    var activeFeedbackButton: RemoteButton? {
        illustrationView.activeFeedbackButton
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: usesCompactLayout
                ? XiaomiRemote2ProDiagramSpec.compactHeight
                : XiaomiRemote2ProDiagramSpec.regularHeight
        )
    }

    override init(frame frameRect: NSRect) {
        illustrationView = RemoteControlIllustrationView(frame: .zero)
        super.init(frame: frameRect)
        configureView()
    }

    init(frame frameRect: NSRect, imageProvider: @escaping () -> NSImage?) {
        illustrationView = RemoteControlIllustrationView(
            frame: .zero,
            imageProvider: imageProvider
        )
        super.init(frame: frameRect)
        configureView()
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(illustrationView)
        recentButtonLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        recentButtonLabel.textColor = UITheme.waterInkMistBlue
        recentButtonLabel.alignment = .center
        recentButtonLabel.isHidden = true
        recentButtonLabel.setAccessibilityElement(true)
        recentButtonLabel.setAccessibilityRole(.staticText)
        addSubview(recentButtonLabel)
        for item in XiaomiRemote2ProDiagramSpec.items {
            let callout = RemoteButtonCalloutView(
                button: item.button,
                alignment: item.side == .left ? .right : .left
            )
            calloutViews[item.button] = callout
            addSubview(callout)
        }
        apply(mapping: .defaults)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let compact = bounds.width > 0 && bounds.width < XiaomiRemote2ProDiagramSpec.compactBreakpoint
        if compact != usesCompactLayout {
            usesCompactLayout = compact
            invalidateIntrinsicContentSize()
        }
        if compact {
            layoutCompact()
        } else {
            layoutRegular()
        }
    }

    func apply(mapping: RemoteButtonMapping) {
        currentMapping = mapping
        for button in RemoteButton.allCases {
            let action = mapping.action(for: button)
            calloutViews[button]?.apply(action: action)
        }
        updateRecentButtonLabel()
    }

    func apply(
        mapping: RemoteButtonMapping,
        pressedButton: RemoteButton?,
        clearsImmediately: Bool = false
    ) {
        apply(mapping: mapping)
        if let pressedButton {
            lastRecognizedButton = pressedButton
            updateRecentButtonLabel()
        }
        illustrationView.setPressedButton(
            pressedButton,
            clearsImmediately: clearsImmediately
        )
    }

    func preview(button: RemoteButton) {
        lastRecognizedButton = button
        updateRecentButtonLabel()
        illustrationView.setPressedButton(button)
        illustrationView.setPressedButton(nil)
    }

    private func layoutRegular() {
        illustrationView.showsConnectors = true
        illustrationView.frame = bounds
        layoutRecentButtonLabel()
        let bodyRect = XiaomiRemote2ProDiagramSpec.bodyRect(in: bounds)
        let labelHeight: CGFloat = 36
        let outerMargin: CGFloat = 2
        let innerGap = XiaomiRemote2ProDiagramSpec.connectorGap + 8
        let leftWidth = max(120, bodyRect.minX - innerGap - outerMargin)
        let rightX = bodyRect.maxX + innerGap
        let rightWidth = max(120, bounds.maxX - rightX - outerMargin)

        for item in XiaomiRemote2ProDiagramSpec.items {
            guard let callout = calloutViews[item.button] else { continue }
            let centerY = bodyRect.minY + item.calloutY * bodyRect.height
            let y = min(max(0, centerY - labelHeight / 2), bounds.height - labelHeight)
            switch item.side {
            case .left:
                callout.frame = CGRect(x: outerMargin, y: y, width: leftWidth, height: labelHeight)
            case .right:
                callout.frame = CGRect(x: rightX, y: y, width: rightWidth, height: labelHeight)
            }
        }
    }

    private func layoutCompact() {
        illustrationView.showsConnectors = false
        illustrationView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: XiaomiRemote2ProDiagramSpec.regularHeight
        )
        layoutRecentButtonLabel()
        let columnGap: CGFloat = 12
        let margin: CGFloat = 2
        let columnWidth = max(120, (bounds.width - margin * 2 - columnGap) / 2)
        let rightX = margin + columnWidth + columnGap
        let firstRowY = XiaomiRemote2ProDiagramSpec.regularHeight + 14
        let rowHeight: CGFloat = 41

        for item in XiaomiRemote2ProDiagramSpec.items {
            guard let callout = calloutViews[item.button] else { continue }
            let x = item.side == .left ? margin : rightX
            callout.frame = CGRect(
                x: x,
                y: firstRowY + CGFloat(item.order) * rowHeight,
                width: columnWidth,
                height: 36
            )
        }
    }

    private func layoutRecentButtonLabel() {
        recentButtonLabel.frame = CGRect(
            x: max(0, bounds.midX - 150),
            y: 0,
            width: min(300, bounds.width),
            height: 18
        )
    }

    private func updateRecentButtonLabel() {
        guard let button = lastRecognizedButton else {
            recentButtonLabel.isHidden = true
            return
        }
        let action = currentMapping.action(for: button)
        let text = "刚刚识别：\(RemoteButtonPresentation.title(for: button)) · \(RemoteButtonPresentation.actionDetail(for: action, button: button))"
        recentButtonLabel.stringValue = text
        recentButtonLabel.setAccessibilityLabel(text)
        recentButtonLabel.isHidden = false
    }
}

@MainActor
private final class RemoteButtonCalloutView: NSView {
    private let button: RemoteButton
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField

    override var isFlipped: Bool { true }

    init(button: RemoteButton, alignment: NSTextAlignment) {
        self.button = button
        titleLabel = NSTextField(labelWithString: RemoteButtonPresentation.title(for: button))
        detailLabel = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = UITheme.waterInkText
        titleLabel.alignment = alignment
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byClipping

        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = UITheme.waterInkMuted
        detailLabel.alignment = alignment
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byClipping

        titleLabel.setAccessibilityElement(false)
        detailLabel.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        addSubview(titleLabel)
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = CGRect(x: 0, y: 1, width: bounds.width, height: 15)
        detailLabel.frame = CGRect(x: 0, y: 18, width: bounds.width, height: 15)
    }

    func apply(action: RemoteButtonAction) {
        let title = RemoteButtonPresentation.title(for: button)
        let detail = RemoteButtonPresentation.actionDetail(for: action, button: button)
        titleLabel.stringValue = title
        detailLabel.stringValue = "当前：\(detail)"
        setAccessibilityLabel("\(title)，当前功能：\(detail)")
    }
}
