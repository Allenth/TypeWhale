import AppKit

// 稳定双区布局：左侧是当前语音工作区，右侧是按目的分组的控制面板。
// 右侧内容只允许纵向滚动，避免横向裁切破坏设置的空间稳定感。
extension MainViewController {

    // MARK: - 顶层装配

    func buildMainSurface() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let topBar = buildTopBar()
        container.addSubview(topBar)

        wireHotkeyButtons()

        let session = panel("当前会话", width: 300, fillsHeight: true, buildSessionAndRecentContent())
        let inspector = panel("控制面板", width: 620, fillsHeight: true, buildInspectorTabs())
        container.addSubview(session)
        container.addSubview(inspector)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            session.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            session.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            session.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            inspector.leadingAnchor.constraint(equalTo: session.trailingAnchor, constant: 14),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            inspector.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    private func buildTopBar() -> NSView {
        let icon = NSImageView()
        icon.image = loadBrandIcon()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 7
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let title = label(AppBrand.displayName, size: 15, weight: .semibold)
        let version = label(versionText(), size: 10, weight: .medium)
        version.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, version])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0

        let usageGuideButton = footerIconButton(title: "使用方法", symbolName: "questionmark.circle", action: #selector(showUsageGuide(_:)))
        let historyButton = footerIconButton(title: "版本历史", symbolName: "clock.arrow.circlepath", action: #selector(showVersionHistory(_:)))
        let testLogsButton = footerIconButton(title: "测试日志", symbolName: "doc.text.magnifyingglass", action: #selector(showTestLogs(_:)))

        // 左上角让开窗口红绿灯（交通灯）按钮，避免 logo/标题被遮挡。
        let trafficLightPad = NSView()
        trafficLightPad.translatesAutoresizingMaskIntoConstraints = false
        trafficLightPad.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let row = NSStackView(views: [trafficLightPad, icon, titleStack, flexSpacer(), memoryLabel, usageGuideButton, historyButton, testLogsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        memoryLabel.textColor = .secondaryLabelColor
        memoryLabel.toolTip = "\(AppBrand.displayName) 当前物理内存占用（与活动监视器“内存”一致）"
        updateMemoryReadout()
        return row
    }

    // MARK: - 面板容器（明确边界）

    private func panel(_ title: String, width: CGFloat, fillsHeight: Bool = false, _ content: NSView) -> NSView {
        let header = panelTitleLabel(title)

        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.045).cgColor
        box.layer?.cornerRadius = UILayout.cornerRadius
        box.layer?.borderWidth = 1
        box.layer?.borderColor = UITheme.cardBorder.cgColor
        box.addSubview(stack)
        // fillsHeight=true：内容栈底边钉到面板底，让低 hugging 的子视图（如最近转录）撑满整列。
        let bottom = fillsHeight
            ? stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14)
            : stack.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -14)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            bottom,
        ])
        return box
    }

    private func rowStack(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        for r in rows { r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    // MARK: - Inspector tabs

    func buildInspectorTabs() -> NSView {
        applyInspectorControlSizingIfNeeded()
        inspectorTabButtons.removeAll()
        inspectorContent.translatesAutoresizingMaskIntoConstraints = false
        inspectorContent.wantsLayer = true

        inspectorScroll.translatesAutoresizingMaskIntoConstraints = false
        inspectorScroll.documentView = inspectorContent
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.hasHorizontalScroller = false
        inspectorScroll.autohidesScrollers = true
        inspectorScroll.drawsBackground = false
        inspectorScroll.borderType = .noBorder
        inspectorScroll.horizontalScrollElasticity = .none
        inspectorScroll.verticalScrollElasticity = .allowed
        inspectorScroll.automaticallyAdjustsContentInsets = false

        let tabs = MainInspectorTab.allCases.map { tab -> NSButton in
            let button = NSButton(title: tab.title, target: self, action: #selector(handleInspectorTab(_:)))
            button.setButtonType(.toggle)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.attributedTitle = NSAttributedString(string: tab.title, attributes: inspectorTabTitleAttributes(isSelected: false))
            button.tag = MainInspectorTab.allCases.firstIndex(of: tab) ?? 0
            button.setAccessibilityLabel("\(tab.title)设置")
            button.widthAnchor.constraint(equalToConstant: 84).isActive = true
            inspectorTabButtons[tab] = button
            return button
        }

        let tabRow = NSStackView(views: tabs)
        tabRow.orientation = .horizontal
        tabRow.alignment = .centerY
        tabRow.spacing = 6
        tabRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [tabRow, inspectorScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        inspectorScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        inspectorScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        inspectorScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        inspectorContent.widthAnchor.constraint(equalTo: inspectorScroll.contentView.widthAnchor).isActive = true

        selectInspectorTab(.common)
        return stack
    }

    private func applyInspectorControlSizingIfNeeded() {
        guard !didApplyInspectorControlSizing else { return }
        didApplyInspectorControlSizing = true

        smartRewriteMode.widthAnchor.constraint(equalToConstant: 96).isActive = true
        translationDirectionMode.widthAnchor.constraint(equalToConstant: 88).isActive = true
        screenshotSaveLocationButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        audioInputDeviceMode.widthAnchor.constraint(equalToConstant: 142).isActive = true
        audioInputRefreshButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        audioInputRefreshButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        smartAIModelMode.widthAnchor.constraint(equalToConstant: 132).isActive = true

        [autoScopeButton, promptSettingsButton, developerTermsButton, translationPromptButton, socialScopeButton,
         deepSeekKeyButton, deepSeekBalanceButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: 92).isActive = true
        }
    }

    @objc func handleInspectorTab(_ sender: NSButton) {
        let tabs = MainInspectorTab.allCases
        guard sender.tag >= 0, sender.tag < tabs.count else { return }
        selectInspectorTab(tabs[sender.tag])
    }

    func selectInspectorTab(_ tab: MainInspectorTab) {
        selectedInspectorTab = tab
        inspectorTabButtons.forEach { key, button in
            let isSelected = key == tab
            button.state = isSelected ? .on : .off
            button.contentTintColor = isSelected ? UITheme.brandYellow : .secondaryLabelColor
            button.attributedTitle = NSAttributedString(
                string: key.title,
                attributes: inspectorTabTitleAttributes(isSelected: isSelected)
            )
        }
        inspectorContent.subviews.forEach { $0.removeFromSuperview() }
        let page = buildInspectorPage(tab)
        page.translatesAutoresizingMaskIntoConstraints = false
        inspectorContent.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: inspectorContent.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: inspectorContent.trailingAnchor),
            page.topAnchor.constraint(equalTo: inspectorContent.topAnchor),
            page.bottomAnchor.constraint(equalTo: inspectorContent.bottomAnchor),
        ])
        inspectorScroll.contentView.scroll(to: .zero)
        inspectorScroll.reflectScrolledClipView(inspectorScroll.contentView)
    }

    func buildInspectorPage(_ tab: MainInspectorTab) -> NSView {
        switch tab {
        case .common:
            return inspectorPage([
                inspectorGroup("预览主题", buildPreviewThemeContent(), prominence: .lead),
                inspectorGroup("快捷设置", buildQuickSettingsCardContent()),
                inspectorGroup("截图", buildScreenshotSettingsContent()),
                inspectorGroup("系统", buildSystemSettingsContent()),
            ])
        case .intelligence:
            return inspectorPage([
                inspectorGroup("智能整理", buildSmartRewritePanelContent()),
            ])
        case .hotkeys:
            return inspectorPage([
                inspectorGroup("快捷键", buildHotkeysPanelContent()),
            ])
        case .status:
            return inspectorPage([
                inspectorGroup("模型", buildManagedModelContent()),
                inspectorGroup("状态", buildStatusPanelContent()),
            ])
        }
    }

    private func buildManagedModelContent() -> NSView {
        managedASRModelListView
    }

    private func inspectorPage(_ groups: [NSView]) -> NSView {
        let stack = FlippedStackView(views: groups)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.groupSpacing
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        groups.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func inspectorGroup(_ title: String, _ body: NSView, prominence: InspectorGroupProminence = .standard) -> NSView {
        let header = inspectorGroupTitleLabel(title)
        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return inspectorGroupBox(stack, prominence: prominence)
    }

    // 第二列：预览主题。两张程序绘制的迷你预览，点击切换主题。
    private func buildPreviewThemeContent() -> NSView {
        let classicTile = ThemePreviewTile(kind: .classic, title: "默认胶囊")
        let notchTile = ThemePreviewTile(kind: .notch, title: "刘海主题")
        previewThemeClassicTile = classicTile
        previewThemeNotchTile = notchTile
        classicTile.onSelect = { [weak self] in self?.selectPreviewTheme(.classic) }
        notchTile.onSelect = { [weak self] in self?.selectPreviewTheme(.notch) }
        let current = AppSettingsStore.loadMainViewSettings().previewTheme
        classicTile.isSelected = current == .classic
        notchTile.isSelected = current == .notch

        let stack = NSStackView(views: [classicTile, notchTile])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for tile in [classicTile, notchTile] {
            tile.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// 点击预览瓦片切换主题：存盘并刷新选中高亮。
    func selectPreviewTheme(_ theme: PreviewTheme) {
        selectedPreviewTheme = theme
        saveSettings()
        refreshPreviewThemeTiles()
    }

    func refreshPreviewThemeTiles() {
        let current = previewTheme
        previewThemeClassicTile?.isSelected = current == .classic
        previewThemeNotchTile?.isSelected = current == .notch
    }

    // 子分区：在一列里用小标题 + 分隔线划清边界。
    private func subSection(_ title: String, _ rows: [NSView]) -> NSView {
        subSectionView(title, rowStack(rows))
    }

    private func subSectionView(_ title: String, _ body: NSView) -> NSView {
        let header = inspectorGroupTitleLabel(title)
        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.compactGroupSpacing - 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // 快捷设置 + 智能整理 合并为一列，两个子分区用分隔线划清边界。
    private func buildComboQuickSmartContent() -> NSView {
        let quick = subSectionView("快捷设置", buildQuickSettingsCardContent())
        let smart = subSectionView("智能整理", buildSmartRewritePanelContent())
        let divider = hairlineView()
        let stack = NSStackView(views: [quick, divider, smart])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.groupSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        [quick, divider, smart].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func buildScreenshotSettingsContent() -> NSView {
        return rowStack([
            optionRow("保存位置", screenshotSaveLocationButton),
        ])
    }

    private func buildSystemSettingsContent() -> NSView {
        let audioInputControls = NSStackView(views: [audioInputDeviceMode, audioInputRefreshButton])
        audioInputControls.orientation = .horizontal
        audioInputControls.alignment = .centerY
        audioInputControls.spacing = 4
        return rowStack([
            optionRow("输入设备", audioInputControls),
            optionRow("胶囊实时预览", realtime),
            optionRow("停顿自动完成", autoFinish),
            optionRow("录音时降低系统音量", duckSystemAudio),
            optionRow("麦克风降噪（增强·略慢）", micNoiseReduction),
            optionRow("开机自动启动", launchAtLogin),
        ])
    }

    private func buildSessionAndRecentContent() -> NSView {
        let sessionPanel = buildSessionPanel()
        sessionPanel.setContentHuggingPriority(.required, for: .vertical)

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
        let recentCard = roundedBox(recentScroll, hPad: 8, vPad: 6)

        let recentHeader = inspectorGroupTitleLabel("最近转录")

        let stack = NSStackView(views: [sessionPanel, recentHeader, recentCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        sessionPanel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        recentCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        recentScroll.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor).isActive = true
        recentStack.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor).isActive = true
        // 整个内容栈吸收面板多余高度，再由低 hugging 的最近转录卡片撑满。
        stack.setContentHuggingPriority(.defaultLow, for: .vertical)
        recentCard.setContentHuggingPriority(.defaultLow, for: .vertical)
        recentScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        return stack
    }

    private func buildQuickSettingsCardContent() -> NSView {
        smartRewriteMode.controlSize = .small
        translationDirectionMode.controlSize = .small
        smartRewriteMode.font = .systemFont(ofSize: 11, weight: .medium)
        translationDirectionMode.font = .systemFont(ofSize: 11, weight: .medium)
        return rowStack([
            compactOptionRow("整理模式", smartRewriteMode),
            compactOptionRow("自动翻译", autoTranslate),
            compactOptionRow("翻译方向", translationDirectionMode),
        ])
    }

    private func buildStatusPanelContent() -> NSView {
        let model = buildModelEntry()
        let permission = buildPermissionEntry()
        let stack = NSStackView(views: [model, permission])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        model.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        permission.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func buildSmartRewritePanelContent() -> NSView {
        [autoScopeButton, promptSettingsButton, developerTermsButton, translationPromptButton, socialScopeButton, deepSeekKeyButton, deepSeekBalanceButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        let keyRow = optionRow("DeepSeek Key", deepSeekKeyButton)
        let usageRow = optionRow("费用 / 余额", deepSeekBalanceButton)
        smartAIKeyRow = keyRow
        smartAIUsageRow = usageRow
        refreshSmartAIUsageVisibility()
        return rowStack([
            optionRow("整理模型", smartAIModelMode),
            optionRow("自动范围", autoScopeButton),
            optionRow("整理提示词", promptSettingsButton),
            optionRow("开发术语", developerTermsButton),
            optionRow("翻译提示词", translationPromptButton),
            optionRow("社交清单", socialScopeButton),
            keyRow,
            usageRow,
        ])
    }

    private func buildHotkeysPanelContent() -> NSView {
        return rowStack([
            shortcutRow(title: "主快捷键", captureButton: hotkeyCaptureButton, fallbackButton: hotkeyResetButton),
            shortcutRow(title: "备用快捷键", captureButton: secondaryHotkeyCaptureButton, fallbackButton: secondaryHotkeyClearButton),
            shortcutRow(title: "截图快捷键", captureButton: screenshotHotkeyCaptureButton, fallbackButton: screenshotHotkeyResetButton),
            shortcutRow(title: "截图备用", captureButton: secondaryScreenshotHotkeyCaptureButton, fallbackButton: secondaryScreenshotHotkeyClearButton),
            shortcutRow(title: "翻译截图", captureButton: screenshotTranslationHotkeyCaptureButton, fallbackButton: screenshotTranslationHotkeyResetButton),
            shortcutRow(title: "自动翻译", captureButton: autoTranslateHotkeyCaptureButton, fallbackButton: autoTranslateHotkeyClearButton),
            shortcutRow(title: "唤起主页", captureButton: mainWindowHotkeyCaptureButton, fallbackButton: mainWindowHotkeyResetButton),
        ])
    }

    // 快捷键录入按钮的接线与样式（原在偏好弹窗里，现由「快捷键」面板复用）
    func wireHotkeyButtons() {
        [hotkeyValue, secondaryHotkeyValue, screenshotHotkeyValue, secondaryScreenshotHotkeyValue,
         screenshotTranslationHotkeyValue, autoTranslateHotkeyValue, mainWindowHotkeyValue].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
        }
        hotkeyCaptureButton.target = self; hotkeyCaptureButton.action = #selector(beginHotkeyCapture)
        hotkeyResetButton.target = self; hotkeyResetButton.action = #selector(resetHotkey)
        secondaryHotkeyCaptureButton.target = self; secondaryHotkeyCaptureButton.action = #selector(beginSecondaryHotkeyCapture)
        secondaryHotkeyClearButton.target = self; secondaryHotkeyClearButton.action = #selector(clearSecondaryHotkey)
        screenshotHotkeyCaptureButton.target = self; screenshotHotkeyCaptureButton.action = #selector(beginScreenshotHotkeyCapture)
        screenshotHotkeyResetButton.target = self; screenshotHotkeyResetButton.action = #selector(resetScreenshotHotkey)
        secondaryScreenshotHotkeyCaptureButton.target = self; secondaryScreenshotHotkeyCaptureButton.action = #selector(beginSecondaryScreenshotHotkeyCapture)
        secondaryScreenshotHotkeyClearButton.target = self; secondaryScreenshotHotkeyClearButton.action = #selector(clearSecondaryScreenshotHotkey)
        screenshotTranslationHotkeyCaptureButton.target = self; screenshotTranslationHotkeyCaptureButton.action = #selector(beginScreenshotTranslationHotkeyCapture)
        screenshotTranslationHotkeyResetButton.target = self; screenshotTranslationHotkeyResetButton.action = #selector(resetScreenshotTranslationHotkey)
        autoTranslateHotkeyCaptureButton.target = self; autoTranslateHotkeyCaptureButton.action = #selector(beginAutoTranslateHotkeyCapture)
        autoTranslateHotkeyClearButton.target = self; autoTranslateHotkeyClearButton.action = #selector(clearAutoTranslateHotkey)
        mainWindowHotkeyCaptureButton.target = self; mainWindowHotkeyCaptureButton.action = #selector(beginMainWindowHotkeyCapture)
        mainWindowHotkeyResetButton.target = self; mainWindowHotkeyResetButton.action = #selector(clearMainWindowHotkey)
        let captureButtons = [hotkeyCaptureButton, secondaryHotkeyCaptureButton, screenshotHotkeyCaptureButton,
                              secondaryScreenshotHotkeyCaptureButton, screenshotTranslationHotkeyCaptureButton,
                              autoTranslateHotkeyCaptureButton, mainWindowHotkeyCaptureButton]
        let trailingButtons = [hotkeyResetButton, secondaryHotkeyClearButton, screenshotHotkeyResetButton,
                               secondaryScreenshotHotkeyClearButton, screenshotTranslationHotkeyResetButton,
                               autoTranslateHotkeyClearButton, mainWindowHotkeyResetButton]
        (captureButtons + trailingButtons).forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
        }
        captureButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 128).isActive = true }
        trailingButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 70).isActive = true }
    }
}
