import AppKit

final class ASRBackendSegmentedSelector: NSControl {
    struct Item {
        let title: String
        let tag: Int
        let isEnabled: Bool
        let toolTip: String?
    }

    private var buttons: [NSButton] = []
    private var buttonWidths: [CGFloat] = []
    private(set) var selectedTag = 0

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(_ items: [Item], selectedTag: Int) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        buttonWidths.removeAll()
        for item in items {
            let button = NSButton(title: item.title, target: self, action: #selector(selectSegment(_:)))
            button.tag = item.tag
            button.setButtonType(.toggle)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.isEnabled = item.isEnabled
            button.toolTip = item.toolTip
            button.setAccessibilityLabel("识别模型：\(item.title)")
            button.sizeToFit()
            buttonWidths.append(ceil(max(110, button.fittingSize.width)))
            addSubview(button)
            buttons.append(button)
        }
        select(tag: selectedTag)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width
        let height = width > 0
            ? ASRButtonFlowLayout.layout(containerWidth: width, itemWidths: buttonWidths).height
            : ASRButtonFlowLayout.rowHeight + ASRButtonFlowLayout.insets.top + ASRButtonFlowLayout.insets.bottom
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        super.layout()
        let result = ASRButtonFlowLayout.layout(containerWidth: bounds.width, itemWidths: buttonWidths)
        for (button, frame) in zip(buttons, result.frames) {
            button.frame = frame
        }
    }

    func select(tag: Int) {
        selectedTag = tag
        for button in buttons {
            button.state = button.tag == tag ? .on : .off
            button.contentTintColor = button.tag == tag ? .controlAccentColor : nil
        }
    }

    @objc private func selectSegment(_ sender: NSButton) {
        guard sender.isEnabled else { return }
        select(tag: sender.tag)
        sendAction(action, to: target)
    }
}
