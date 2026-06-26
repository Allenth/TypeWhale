import AppKit

extension MainViewController {
    // MARK: - Left column

    func buildLeftColumn() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = UITheme.brandTint.cgColor

        let border = NSView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.backgroundColor = UITheme.cardBorder.cgColor
        container.addSubview(border)

        let brandIcon = NSImageView()
        brandIcon.image = loadBrandIcon()
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.wantsLayer = true
        brandIcon.layer?.cornerRadius = 12
        brandIcon.layer?.masksToBounds = true
        let brandTitle = label("TypeWhale", size: 16, weight: .semibold)
        brandTitle.alignment = .center
        let brandVersion = label(versionText(), size: 10, weight: .medium)
        brandVersion.textColor = .secondaryLabelColor
        brandVersion.alignment = .center
        let brandStack = NSStackView(views: [brandIcon, brandTitle, brandVersion])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 5

        let modelEntry = buildModelEntry()
        let permissionEntry = buildPermissionEntry()
        permissionEntry.setContentHuggingPriority(.required, for: .vertical)
        permissionEntry.setContentCompressionResistancePriority(.required, for: .vertical)

        let usageGuideButton = footerIconButton(
            title: "使用方法",
            symbolName: "questionmark.circle",
            action: #selector(showUsageGuide(_:))
        )
        let historyButton = footerIconButton(
            title: "版本历史",
            symbolName: "clock.arrow.circlepath",
            action: #selector(showVersionHistory(_:))
        )
        let testLogsButton = footerIconButton(
            title: "测试日志",
            symbolName: "doc.text.magnifyingglass",
            action: #selector(showTestLogs(_:))
        )
        let preferencesButton = footerIconButton(
            title: "偏好设置",
            symbolName: "gearshape",
            action: #selector(showPreferencesPopover(_:))
        )

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let footerButtons = NSStackView(views: [flexSpacer(), usageGuideButton, historyButton, testLogsButton, preferencesButton, flexSpacer()])
        footerButtons.orientation = .horizontal
        footerButtons.alignment = .centerY
        footerButtons.distribution = .fill
        footerButtons.spacing = 8
        footerButtons.translatesAutoresizingMaskIntoConstraints = false

        memoryLabel.textColor = .secondaryLabelColor
        memoryLabel.toolTip = "TypeWhale 当前物理内存占用（与活动监视器“内存”一致）"
        updateMemoryReadout()

        let quickSettings = buildSidebarQuickSettings()
        let backlogEntry = buildBacklogEntry()

        let stack = NSStackView(views: [brandStack, modelEntry, permissionEntry, spacer, quickSettings, backlogEntry, memoryLabel, footerButtons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: container.topAnchor),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 0.5),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: leftTopInset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            brandStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            quickSettings.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backlogEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            brandIcon.widthAnchor.constraint(equalToConstant: brandIconVisibleSize),
            brandIcon.heightAnchor.constraint(equalToConstant: brandIconVisibleSize),
        ])
        return container
    }

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

    func buildSidebarQuickSettings() -> NSView {
        smartRewriteMode.widthAnchor.constraint(equalToConstant: 86).isActive = true
        translationDirectionMode.widthAnchor.constraint(equalToConstant: 80).isActive = true
        smartRewriteMode.controlSize = .small
        translationDirectionMode.controlSize = .small
        smartRewriteMode.font = .systemFont(ofSize: 11, weight: .medium)
        translationDirectionMode.font = .systemFont(ofSize: 11, weight: .medium)
        smartRewriteMode.alignment = .right
        translationDirectionMode.alignment = .right
        smartRewriteMode.cell?.alignment = .right
        translationDirectionMode.cell?.alignment = .right

        let rows = [
            compactOptionRow("整理模式", smartRewriteMode),
            compactOptionRow("自动翻译", autoTranslate),
            compactOptionRow("翻译方向", translationDirectionMode),
        ]
        let card = listCard(rows, hPad: 10, vPad: 5)
        return section("快捷设置", card)
    }

    func buildBacklogEntry() -> NSView {
        backlogDirectoryButton.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = compactOptionRow("需求池", backlogDirectoryButton)
        let card = listCard([row], hPad: 10, vPad: 5)
        return section("需求池", card)
    }

    func buildCenterColumn() -> NSView {
        let sessionPanel = buildSessionPanel()
        sessionPanel.setContentHuggingPriority(.required, for: .vertical)
        sessionPanel.setContentCompressionResistancePriority(.required, for: .vertical)

        recentStack.orientation = .vertical
        recentStack.alignment = .width
        recentStack.spacing = 0
        recentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentRecords = loadRecentTranscriptions()
        rebuildRecentRows()
        recentScroll.documentView = recentStack
        recentScroll.hasVerticalScroller = true
        recentScroll.autohidesScrollers = true
        recentScroll.drawsBackground = false
        recentScroll.borderType = .noBorder
        recentScroll.translatesAutoresizingMaskIntoConstraints = false
        recentScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        recentScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let recentCard = roundedBox(recentScroll, hPad: 8, vPad: 6)

        let sessionSection = section("当前会话", sessionPanel)
        let recentSection = section("最近转录", recentCard)
        let sections = [sessionSection, recentSection]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for sectionView in sections {
            sectionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        // 「最近转录」吸收中间栏的多余高度并拉高（可滚动看更多条）；
        // 「当前会话」保持紧凑：实时文本区只占几行，不再撑大整块。窗口固定尺寸，整体仍稳定。
        recentSection.setContentHuggingPriority(.defaultLow, for: .vertical)
        sessionSection.setContentHuggingPriority(.required, for: .vertical)
        sessionSection.setContentCompressionResistancePriority(.required, for: .vertical)
        let sessionMinHeight = sessionPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        let recentMinHeight = recentScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: recentViewportHeight)
        NSLayoutConstraint.activate([
            recentStack.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor),
            sessionMinHeight,
            recentMinHeight,
        ])
        return stack
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

    func buildStatusPanel() -> NSView {
        status.alignment = .center
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping

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
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        pill.layer?.cornerRadius = 12
        pill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.addSubview(pillStack)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.translatesAutoresizingMaskIntoConstraints = false
        processingProgress.style = .bar
        processingProgress.controlSize = .small
        processingProgress.isIndeterminate = true
        processingProgress.isDisplayedWhenStopped = false
        processingProgress.isHidden = true

        let inner = NSStackView(views: [pill, waveform, processingProgress, detail])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.spacing = 11
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

        NSLayoutConstraint.activate([
            pillStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 13),
            pillStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -13),
            pillStack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            pillStack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
            pill.widthAnchor.constraint(lessThanOrEqualTo: inner.widthAnchor, constant: -2),
            waveform.heightAnchor.constraint(equalToConstant: 34),
            waveform.widthAnchor.constraint(equalTo: inner.widthAnchor),
            processingProgress.widthAnchor.constraint(equalTo: inner.widthAnchor, multiplier: 0.78),
            processingProgress.heightAnchor.constraint(equalToConstant: 4),
            box.heightAnchor.constraint(equalToConstant: 142),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -14),
            detail.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return box
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

    func buildRealtimeDraftEntry() -> NSView {
        realtimeDraft.textColor = .secondaryLabelColor
        realtimeDraft.maximumNumberOfLines = 4
        realtimeDraft.lineBreakMode = .byWordWrapping
        (realtimeDraft.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        realtimeDraft.translatesAutoresizingMaskIntoConstraints = false

        let draftContent = NSView()
        draftContent.translatesAutoresizingMaskIntoConstraints = false
        draftContent.addSubview(realtimeDraft)
        NSLayoutConstraint.activate([
            realtimeDraft.leadingAnchor.constraint(equalTo: draftContent.leadingAnchor),
            realtimeDraft.trailingAnchor.constraint(equalTo: draftContent.trailingAnchor),
            realtimeDraft.topAnchor.constraint(equalTo: draftContent.topAnchor),
            realtimeDraft.bottomAnchor.constraint(lessThanOrEqualTo: draftContent.bottomAnchor),
            draftContent.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        return section("实时文本", roundedBox(draftContent, hPad: 12, vPad: 10))
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
