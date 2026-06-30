import AppKit

// 平铺横向滚动布局：所有功能摊开成并排的分区面板，重要/常用在左，低频配置在右，
// 横向滚动即可找到。每个面板有明确边界（圆角描边）。
extension MainViewController {

    // MARK: - 顶层装配

    func buildMainSurface() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let topBar = buildTopBar()
        container.addSubview(topBar)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        panelScrollView = scroll

        wireHotkeyButtons()

        // 当前会话固定在左侧，不随横向滚动移动；窄一些，把更多纵向空间留给最近转录。
        let fixedSession = panel("当前会话", width: 300, fillsHeight: true, buildSessionAndRecentContent())
        container.addSubview(fixedSession)

        let panelViews = buildPanels()
        let panels = NSStackView(views: panelViews)
        panels.orientation = .horizontal
        panels.alignment = .top
        panels.spacing = 14
        panels.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        panels.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = panels
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            fixedSession.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            fixedSession.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            fixedSession.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            scroll.leadingAnchor.constraint(equalTo: fixedSession.trailingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            panels.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            panels.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            panels.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        // 每个面板填满纵向高度
        for p in panelViews {
            p.heightAnchor.constraint(equalTo: panels.heightAnchor).isActive = true
        }
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

        let title = label("TypeWhale", size: 15, weight: .semibold)
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
        memoryLabel.toolTip = "TypeWhale 当前物理内存占用（与活动监视器“内存”一致）"
        updateMemoryReadout()
        return row
    }

    // MARK: - 面板容器（明确边界）

    private func panel(_ title: String, width: CGFloat, fillsHeight: Bool = false, _ content: NSView) -> NSView {
        let header = label(title, size: 12, weight: .semibold)
        header.textColor = UITheme.sectionTitle

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
        box.layer?.cornerRadius = 12
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

    // MARK: - 各分区面板（左=常用，右=低频）

    private func buildPanels() -> [NSView] {
        [
            panel("预览主题", width: 200, buildPreviewThemeContent()),
            panel("整理设置", width: 250, buildComboQuickSmartContent()),
            panel("快捷键", width: 300, buildHotkeysPanelContent()),
            panel("更多设置", width: 276, buildMiscSettingsContent()),
            panel("状态", width: 204, buildStatusPanelContent()),
        ]
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
        let header = label(title, size: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
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
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        [quick, divider, smart].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    // 翻译 / 截图 / 系统 合并为一列（各自内容很少）
    private func buildMiscSettingsContent() -> NSView {
        translationPromptButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        screenshotSaveLocationButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        audioInputDeviceMode.widthAnchor.constraint(equalToConstant: 142).isActive = true
        audioInputRefreshButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        audioInputRefreshButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let audioInputControls = NSStackView(views: [audioInputDeviceMode, audioInputRefreshButton])
        audioInputControls.orientation = .horizontal
        audioInputControls.alignment = .centerY
        audioInputControls.spacing = 4
        let translation = subSection("翻译", [optionRow("翻译提示词", translationPromptButton)])
        let screenshot = subSection("截图", [optionRow("保存位置", screenshotSaveLocationButton)])
        let system = subSection("系统", [
            optionRow("输入设备", audioInputControls),
            optionRow("胶囊实时预览", realtime),
            optionRow("停顿自动完成", autoFinish),
            optionRow("录音时降低系统音量", duckSystemAudio),
            optionRow("麦克风降噪（增强·略慢）", micNoiseReduction),
            optionRow("开机自动启动", launchAtLogin),
        ])
        let d1 = hairlineView(); let d2 = hairlineView()
        let stack = NSStackView(views: [translation, d1, screenshot, d2, system])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        [translation, d1, screenshot, d2, system].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
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

        let recentHeader = label("最近转录", size: 11, weight: .medium)
        recentHeader.textColor = UITheme.sectionTitle

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
        smartRewriteMode.widthAnchor.constraint(equalToConstant: 96).isActive = true
        translationDirectionMode.widthAnchor.constraint(equalToConstant: 88).isActive = true
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
        [autoScopeButton, promptSettingsButton, developerTermsButton, deepSeekKeyButton, deepSeekBalanceButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        autoScopeButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        promptSettingsButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        developerTermsButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        deepSeekKeyButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        deepSeekBalanceButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let usageRow = optionRow("费用 / 余额", deepSeekBalanceButton)
        smartAIUsageRow = usageRow
        refreshSmartAIUsageVisibility()
        return rowStack([
            optionRow("自动范围", autoScopeButton),
            optionRow("整理提示词", promptSettingsButton),
            optionRow("开发术语", developerTermsButton),
            optionRow("DeepSeek Key", deepSeekKeyButton),
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

    // 横向滚动到右侧配置区（供 ⌘, 与状态栏调用，替代原偏好弹窗）
    func scrollToConfigPanels() {
        guard let scroll = panelScrollView,
              let doc = scroll.documentView else { return }
        let maxX = max(0, doc.frame.width - scroll.contentView.bounds.width)
        scroll.contentView.scroll(to: NSPoint(x: maxX * 0.42, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
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
        captureButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 92).isActive = true }
        trailingButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 52).isActive = true }
    }
}
