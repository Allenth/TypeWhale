import AppKit

final class TTSReadingLabView: NSView, NSTextViewDelegate {
    let textView = NSTextView()
    let modelPopup = NSPopUpButton()
    let voicePopup = NSPopUpButton()
    let playButton = NSButton(title: "播放", target: nil, action: nil)
    let replayButton = NSButton(title: "重播最近音频", target: nil, action: nil)
    let recordMyVoiceButton = NSButton(title: "录制我的声音", target: nil, action: nil)
    let statusLabel = NSTextField(wrappingLabelWithString: "正在检查本机已验证模型…")
    let metricsLabel = NSTextField(wrappingLabelWithString: "冷/热启动与性能指标会在播放后显示")

    var onTextChange: ((String) -> Void)?
    var onModelChange: ((Int) -> Void)?
    var onVoiceChange: ((String?) -> Void)?
    var onPlay: (() -> Void)?
    var onReplay: (() -> Void)?
    var onRecordMyVoice: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        textView.font = .systemFont(ofSize: 13)
        textView.textColor = UITheme.waterInkText
        textView.backgroundColor = UITheme.waterInkBackground.withAlphaComponent(0.55)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 120)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 120)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 620,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = self
        textView.setAccessibilityLabel("朗读测试文字")

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        scroll.setAccessibilityLabel("朗读文字输入区")

        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.bezelStyle = .rounded
        modelPopup.controlSize = .regular
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.setAccessibilityLabel("本地朗读模型")
        voicePopup.translatesAutoresizingMaskIntoConstraints = false
        voicePopup.bezelStyle = .rounded
        voicePopup.controlSize = .regular
        voicePopup.target = self
        voicePopup.action = #selector(voiceChanged)
        voicePopup.setAccessibilityLabel("朗读音色")

        [playButton, replayButton, recordMyVoiceButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        playButton.keyEquivalent = "\r"
        playButton.target = self
        playButton.action = #selector(playPressed)
        playButton.setAccessibilityLabel("播放或停止朗读测试")
        replayButton.target = self
        replayButton.action = #selector(replayPressed)
        replayButton.setAccessibilityLabel("重播最近朗读音频")
        recordMyVoiceButton.target = self
        recordMyVoiceButton.action = #selector(recordMyVoicePressed)
        recordMyVoiceButton.setAccessibilityLabel("录制我的声音参考")

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = UITheme.waterInkMuted
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setAccessibilityLabel("朗读测试状态")
        metricsLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        metricsLabel.textColor = UITheme.sectionTitle
        metricsLabel.maximumNumberOfLines = 3
        metricsLabel.lineBreakMode = .byWordWrapping
        metricsLabel.setAccessibilityLabel("朗读性能指标")

        let modelRow = NSStackView(views: [
            NSTextField(labelWithString: "模型"),
            modelPopup,
        ])
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 10
        modelPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let voiceRow = NSStackView(views: [
            NSTextField(labelWithString: "音色"),
            voicePopup,
        ])
        voiceRow.orientation = .horizontal
        voiceRow.alignment = .centerY
        voiceRow.spacing = 10
        voicePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let actionRow = NSStackView(views: [playButton, replayButton, recordMyVoiceButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let stack = NSStackView(
            views: [scroll, modelRow, voiceRow, actionRow, statusLabel, metricsLabel]
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        addSubview(stack)
        [scroll, modelRow, voiceRow, actionRow, statusLabel, metricsLabel].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
    }

    @objc private func modelChanged() {
        onModelChange?(modelPopup.indexOfSelectedItem)
    }

    @objc private func voiceChanged() {
        onVoiceChange?(voicePopup.selectedItem?.representedObject as? String)
    }

    @objc private func playPressed() {
        onPlay?()
    }

    @objc private func replayPressed() {
        onReplay?()
    }

    @objc private func recordMyVoicePressed() {
        onRecordMyVoice?()
    }
}
