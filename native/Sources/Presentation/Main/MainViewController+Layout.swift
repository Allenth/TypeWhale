import AppKit

extension MainViewController {

    func footerIconButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    func buildSessionPanel() -> NSView {
        status.alignment = .center
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        // 说明性文字移到声纹波形右侧，故改为左对齐。
        detail.alignment = .left
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor

        let pillStack = NSStackView(views: [statusDot, status])
        pillStack.orientation = .horizontal
        pillStack.alignment = .centerY
        pillStack.spacing = 7
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pillStack.setContentHuggingPriority(.required, for: .horizontal)

        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        pill.layer?.cornerRadius = 13
        pill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.addSubview(pillStack)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.style = .bar
        processingProgress.controlSize = .small
        processingProgress.isIndeterminate = true
        processingProgress.isDisplayedWhenStopped = false
        processingProgress.isHidden = true

        // 声纹波形（左）｜ 竖线 ｜ 说明性文字（右）
        let waveDivider = NSView()
        waveDivider.translatesAutoresizingMaskIntoConstraints = false
        waveDivider.wantsLayer = true
        waveDivider.layer?.backgroundColor = UITheme.hairline.cgColor
        let waveRow = NSStackView(views: [waveform, waveDivider, detail])
        waveRow.orientation = .horizontal
        waveRow.alignment = .centerY
        waveRow.spacing = 12
        waveRow.translatesAutoresizingMaskIntoConstraints = false

        configureRealtimeTextView()

        let draftCaption = label("实时文本", size: 10, weight: .medium)
        draftCaption.textColor = UITheme.sectionTitle

        let draftStack = NSStackView(views: [draftCaption, realtimeScroll])
        draftStack.orientation = .vertical
        draftStack.alignment = .leading
        draftStack.spacing = 7
        // 实时文本区作为可伸缩区域，吸收卡片多余高度；窗口固定高度下保持稳定。
        draftStack.setContentHuggingPriority(.defaultLow, for: .vertical)
        realtimeScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        draftCaption.setContentHuggingPriority(.required, for: .vertical)

        let divider = hairlineView()
        let pillRow = NSStackView(views: [pill, flexSpacer()])
        pillRow.orientation = .horizontal
        pillRow.alignment = .centerY
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        let inner = NSStackView(views: [pillRow, waveRow, processingProgress, divider, draftStack])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.distribution = .fill
        inner.spacing = 8
        inner.setCustomSpacing(10, after: waveRow)
        inner.detachesHiddenViews = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = UITheme.cardFill.cgColor
        box.layer?.cornerRadius = UILayout.cornerRadius
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = UITheme.cardBorder.cgColor
        box.addSubview(inner)

        // 实时文本区最小高度设为非必需优先级：极端内容时让位给“填满卡片”，避免约束冲突。
        let draftMinHeight = realtimeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        draftMinHeight.priority = NSLayoutConstraint.Priority(740)

        NSLayoutConstraint.activate([
            pillStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 13),
            pillStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -13),
            pillStack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 5),
            pillStack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -5),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
            pill.heightAnchor.constraint(equalToConstant: 26),
            pill.widthAnchor.constraint(lessThanOrEqualTo: inner.widthAnchor),
            pillRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            waveRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 26),
            waveform.widthAnchor.constraint(equalToConstant: 96),
            waveDivider.widthAnchor.constraint(equalToConstant: 1),
            waveDivider.heightAnchor.constraint(equalToConstant: 22),
            processingProgress.widthAnchor.constraint(equalTo: inner.widthAnchor, multiplier: 0.56),
            processingProgress.heightAnchor.constraint(equalToConstant: 4),
            divider.widthAnchor.constraint(equalTo: inner.widthAnchor),
            draftStack.widthAnchor.constraint(equalTo: inner.widthAnchor),
            realtimeScroll.widthAnchor.constraint(equalTo: draftStack.widthAnchor),
            draftMinHeight,
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        return box
    }

    func configureRealtimeTextView() {
        realtimeTextView.isEditable = false
        realtimeTextView.isSelectable = true
        realtimeTextView.drawsBackground = false
        realtimeTextView.textColor = NSColor(calibratedWhite: 1, alpha: 0.82)
        realtimeTextView.font = .systemFont(ofSize: 13)
        realtimeTextView.textContainerInset = NSSize(width: 0, height: 2)
        realtimeTextView.textContainer?.lineFragmentPadding = 0
        realtimeTextView.isVerticallyResizable = true
        realtimeTextView.isHorizontallyResizable = false
        realtimeTextView.autoresizingMask = [.width]
        realtimeTextView.textContainer?.widthTracksTextView = true
        realtimeTextView.minSize = NSSize(width: 0, height: 0)
        realtimeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        realtimeTextView.string = "等待实时文本"

        realtimeScroll.documentView = realtimeTextView
        realtimeScroll.hasVerticalScroller = false
        realtimeScroll.hasHorizontalScroller = false
        realtimeScroll.drawsBackground = false
        realtimeScroll.borderType = .noBorder
        realtimeScroll.automaticallyAdjustsContentInsets = false
        realtimeScroll.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 刷新左栏内存读数，并按阈值变色；升级到更高档位时给一次提醒。
    func updateMemoryReadout() {
        let megabytes = MemoryMonitor.currentFootprintMB
        memoryLabel.stringValue = "内存 \(megabytes) MB · 峰值 \(MemoryMonitor.peakFootprintMB) MB"
        let level = MemoryMonitor.level(forMB: megabytes)
        switch level {
        case .normal: memoryLabel.textColor = .secondaryLabelColor
        case .warn: memoryLabel.textColor = .systemOrange
        case .high: memoryLabel.textColor = .systemRed
        }
        // 升到预警档位（默认 1GB）时弹一次提示。
        if level != .normal, lastMemoryLevel == .normal {
            detail.stringValue = "内存达到 \(megabytes) MB（预警阈值 \(MemoryMonitor.warnThresholdMB) MB）。可重启 App 释放，或避免超长录音。"
        }
        lastMemoryLevel = level
    }

    /// 当前内存是否处于预警/高档位，供胶囊在录音时同步状态色与提示。
    var isMemoryElevated: Bool {
        MemoryMonitor.level(forMB: MemoryMonitor.currentFootprintMB) != .normal
    }

    /// 更新实时文本区，并滚动到末尾：始终显示最新内容，最旧的被挤到上方滚出可视区。
    func updateRealtimeDraft(_ text: String) {
        let value = text.isEmpty ? " " : text
        if realtimeTextView.string != value {
            realtimeTextView.string = value
        }
        if let container = realtimeTextView.textContainer {
            realtimeTextView.layoutManager?.ensureLayout(for: container)
        }
        realtimeTextView.scrollToEndOfDocument(nil)
    }

    func buildModelEntry() -> NSView {
        let caption = label("当前模型", size: 10, weight: .medium)
        caption.textColor = UITheme.sectionTitle
        modelEntryName.maximumNumberOfLines = 1
        modelEntryName.lineBreakMode = .byTruncatingTail

        let chevron = symbolIcon("chevron.right", size: 12, color: NSColor(calibratedWhite: 1, alpha: 0.35))
        let nameRow = NSStackView(views: [modelEntryName, flexSpacer(), chevron])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8

        modelEntryDot.translatesAutoresizingMaskIntoConstraints = false
        modelEntryDot.wantsLayer = true
        modelEntryDot.layer?.cornerRadius = 3
        modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        modelEntryStatus.textColor = .secondaryLabelColor
        let statusRow = NSStackView(views: [modelEntryDot, modelEntryStatus])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 5

        let textStack = NSStackView(views: [caption, nameRow, statusRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let box = roundedBox(textStack, hPad: 13, vPad: 10)
        NSLayoutConstraint.activate([
            modelEntryDot.widthAnchor.constraint(equalToConstant: 6),
            modelEntryDot.heightAnchor.constraint(equalToConstant: 6),
            nameRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(showModelDetail(_:)))
        box.addGestureRecognizer(click)
        return box
    }

    func buildPermissionEntry() -> NSView {
        let micButton = sidebarPermissionButton(accessibilityLabel: "打开麦克风权限设置", action: #selector(openMicrophone))
        let accessButton = sidebarPermissionButton(accessibilityLabel: "打开辅助功能权限设置", action: #selector(openAccessibility))
        let screenButton = sidebarPermissionButton(accessibilityLabel: "打开屏幕录制权限设置", action: #selector(openScreenRecording))
        let keyboardButton = sidebarPermissionButton(accessibilityLabel: "打开全局快捷键设置", action: #selector(openKeyboard))
        let card = listCard([
            sidebarPermissionRow(icon: "mic", name: "麦克风", status: micStatus, button: micButton),
            sidebarPermissionRow(icon: "accessibility", name: "辅助功能", status: accessibilityStatus, button: accessButton),
            sidebarPermissionRow(icon: "rectangle.on.rectangle", name: "截图权限", status: screenRecordingStatus, button: screenButton),
            sidebarPermissionRow(icon: "keyboard", name: "快捷键", status: hotkeyStatus, button: keyboardButton),
        ], hPad: 9, vPad: 2)
        return section("权限", card)
    }

    func sidebarPermissionButton(accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: accessibilityLabel)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    func sidebarPermissionRow(icon: String, name: String, status: NSTextField, button: NSButton) -> NSView {
        let iconView = symbolIcon(icon, size: 13)
        let nameLabel = label(name, size: 11, weight: .medium)
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        status.font = .systemFont(ofSize: 10, weight: .medium)
        status.alignment = .left
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [nameLabel, status])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconView, textStack, flexSpacer(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return row
    }
}
