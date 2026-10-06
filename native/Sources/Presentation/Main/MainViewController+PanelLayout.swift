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
        title.textColor = UITheme.waterInkText
        let version = label(versionText(), size: 10, weight: .medium)
        version.textColor = UITheme.waterInkMuted
        let titleStack = NSStackView(views: [title, version])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0

        let fullExitButton = NSButton(title: "完全退出", target: self, action: #selector(requestFullAppExit(_:)))
        fullExitButton.bezelStyle = .rounded
        fullExitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: "完全退出")
        fullExitButton.imagePosition = .imageLeading
        fullExitButton.font = .systemFont(ofSize: 11, weight: .semibold)
        fullExitButton.contentTintColor = .systemRed
        fullExitButton.toolTip = "完全退出 \(AppBrand.displayName)"
        fullExitButton.setContentHuggingPriority(.required, for: .horizontal)
        fullExitButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let usageGuideButton = footerIconButton(title: "使用方法", symbolName: "questionmark.circle", action: #selector(showUsageGuide(_:)))
        let historyButton = footerIconButton(title: "版本历史", symbolName: "clock.arrow.circlepath", action: #selector(showVersionHistory(_:)))
        let testLogsButton = footerIconButton(title: "测试日志", symbolName: "doc.text.magnifyingglass", action: #selector(showTestLogs(_:)))
        let mouseShortcutTestButton = footerIconButton(title: "测试鼠标键", symbolName: "mouse", action: #selector(showMouseShortcutTest(_:)))
        // 调试：晨雾浅色 / 深色主题切换（方案 C 逐步落地）。切换后自动重启生效。
        let themeToggleButton = footerIconButton(
            title: AppSettingsStore.useMistLightTheme ? "切到深色（调试）" : "切到晨雾浅色（调试）",
            symbolName: AppSettingsStore.useMistLightTheme ? "moon.stars" : "sun.max",
            action: #selector(toggleMistThemeDebug(_:))
        )

        // 左上角让开窗口红绿灯（交通灯）按钮，避免 logo/标题被遮挡。
        let trafficLightPad = NSView()
        trafficLightPad.translatesAutoresizingMaskIntoConstraints = false
        trafficLightPad.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let row = NSStackView(views: [trafficLightPad, icon, titleStack, fullExitButton, flexSpacer(), memoryLabel, themeToggleButton, usageGuideButton, historyButton, testLogsButton, mouseShortcutTestButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        memoryLabel.textColor = UITheme.waterInkMuted
        memoryLabel.toolTip = "\(AppBrand.displayName) 主进程与本地模型 Worker 的总物理内存占用"
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
        box.layer?.backgroundColor = UITheme.panelFill.cgColor
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

        inspectorTabControl.target = self
        inspectorTabControl.action = #selector(handleInspectorTab(_:))
        inspectorTabControl.segmentStyle = .rounded
        inspectorTabControl.controlSize = .regular
        inspectorTabControl.font = .systemFont(ofSize: 12, weight: .semibold)
        inspectorTabControl.setAccessibilityLabel("控制面板分类")
        inspectorTabControl.translatesAutoresizingMaskIntoConstraints = false
        MainInspectorTab.allCases.enumerated().forEach { index, tab in
            inspectorTabControl.setLabel(tab.title, forSegment: index)
            inspectorTabControl.setWidth(tab == .openClaw ? 96 : 84, forSegment: index)
            inspectorTabControl.setToolTip("\(tab.title)设置", forSegment: index)
        }

        let tabCenteringRow = NSView()
        tabCenteringRow.translatesAutoresizingMaskIntoConstraints = false
        tabCenteringRow.addSubview(inspectorTabControl)

        NSLayoutConstraint.activate([
            inspectorTabControl.centerXAnchor.constraint(equalTo: tabCenteringRow.centerXAnchor),
            inspectorTabControl.topAnchor.constraint(equalTo: tabCenteringRow.topAnchor),
            inspectorTabControl.bottomAnchor.constraint(equalTo: tabCenteringRow.bottomAnchor),
        ])

        let stack = NSStackView(views: [tabCenteringRow, inspectorScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabCenteringRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
        ideaPillRewriteMode.widthAnchor.constraint(equalToConstant: 120).isActive = true
        translationDirectionMode.widthAnchor.constraint(equalToConstant: 142).isActive = true
        screenshotSaveLocationButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        screenshotArchiveMode.widthAnchor.constraint(equalToConstant: 120).isActive = true
        audioInputDeviceMode.widthAnchor.constraint(equalToConstant: 142).isActive = true
        audioInputRefreshButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        audioInputRefreshButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        smartAIModelMode.widthAnchor.constraint(equalToConstant: 240).isActive = true
        modelTabSmartAIModelMode.widthAnchor.constraint(equalToConstant: 240).isActive = true
        openClawGatewayField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        openClawAgentField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        openClawSessionField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        openClawCLIPathField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        openClawCheckButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        openClawVoiceMode.widthAnchor.constraint(equalToConstant: 180).isActive = true
        openClawVoicePlaybackMode.widthAnchor.constraint(equalToConstant: 180).isActive = true
        openClawVoiceInterruptMode.widthAnchor.constraint(equalToConstant: 180).isActive = true
        openClawVoiceVolumeSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        openClawVoiceVolumeValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        openClawVoiceRateSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        openClawVoiceRateValue.widthAnchor.constraint(equalToConstant: 44).isActive = true

        [autoScopeButton, promptSettingsButton, developerTermsButton, translationPromptButton, socialScopeButton,
         deepSeekKeyButton, deepSeekBalanceButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: 92).isActive = true
        }
    }

    @objc func handleInspectorTab(_ sender: NSSegmentedControl) {
        let tabs = MainInspectorTab.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < tabs.count else { return }
        selectInspectorTab(tabs[sender.selectedSegment])
    }

    func selectInspectorTab(_ tab: MainInspectorTab) {
        if isCapturingHotkey {
            endHotkeyCapture()
            refreshHotkeyLabels()
        }
        selectedInspectorTab = tab
        if let index = MainInspectorTab.allCases.firstIndex(of: tab) {
            inspectorTabControl.selectedSegment = index
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
                inspectorGroup("状态", buildStatusPanelContent()),
                inspectorGroup("录音与预览", buildRecordingPreviewSettingsContent()),
                inspectorGroup("粘贴与发送", buildPasteAndSendSettingsContent()),
                inspectorGroup("截图", buildScreenshotSettingsContent()),
                inspectorGroup("系统", buildSystemSettingsContent()),
                inspectorGroup("预览主题", buildPreviewThemeContent(), prominence: .lead),
            ])
        case .intelligence:
            return inspectorPage([
                inspectorGroup("智能整理", buildSmartRewritePanelContent()),
            ])
        case .models:
            return inspectorPage([
                inspectorGroup("ASR 模型", buildManagedModelContent()),
                inspectorGroup("整理模型", buildModelTabSmartAIModelContent()),
            ])
        case .openClaw:
            return inspectorPage([
                inspectorGroup("OpenClaw", buildOpenClawPanelContent(), prominence: .lead),
            ])
        case .voice:
            return inspectorPage([
                inspectorGroup("麦克风", buildPrimaryMicrophoneContent()),
                inspectorGroup("麦克风策略", buildBluetoothMicPreferenceContent()),
                inspectorGroup("小龙虾声音", buildOpenClawVoicePanelContent(), prominence: .lead),
                inspectorGroup("朗读测试", buildTTSReadingLabContent(), prominence: .lead),
            ])
        case .remote:
            return buildRemoteInspectorPage()
        case .hotkeys:
            return inspectorPage([
                inspectorGroup("快捷键", buildHotkeysPanelContent()),
            ])
        }
    }

    private func buildManagedModelContent() -> NSView {
        asrBenchmarkButton.target = self
        asrBenchmarkButton.action = #selector(showASRBenchmark)
        asrBenchmarkButton.bezelStyle = .rounded
        asrBenchmarkButton.toolTip = "用同一段录音逐个比较本机 ASR 模型速度、结果与热词命中"
        let stack = NSStackView(views: [asrBenchmarkButton, managedASRModelListView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        asrBenchmarkButton.setContentHuggingPriority(.required, for: .horizontal)
        managedASRModelListView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
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

    // 外观偏好：三张截图式主题预览并排显示，点击切换胶囊主题。
    private func buildPreviewThemeContent() -> NSView {
        let classicTile = ThemePreviewTile(kind: .classic, title: "默认胶囊")
        let notchTile = ThemePreviewTile(kind: .notch, title: "刘海主题")
        let minimalBlackTile = ThemePreviewTile(kind: .minimalBlack, title: "简洁黑色")
        previewThemeClassicTile = classicTile
        previewThemeNotchTile = notchTile
        previewThemeMinimalBlackTile = minimalBlackTile
        classicTile.onSelect = { [weak self] in self?.selectPreviewTheme(.classic) }
        notchTile.onSelect = { [weak self] in self?.selectPreviewTheme(.notch) }
        minimalBlackTile.onSelect = { [weak self] in self?.selectPreviewTheme(.minimalBlack) }
        let current = AppSettingsStore.loadMainViewSettings().previewTheme
        classicTile.isSelected = current == .classic
        notchTile.isSelected = current == .notch
        minimalBlackTile.isSelected = current == .minimalBlack

        let stack = NSStackView(views: [classicTile, notchTile, minimalBlackTile])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
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
        previewThemeMinimalBlackTile?.isSelected = current == .minimalBlack
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

    private func buildPasteAndSendSettingsContent() -> NSView {
        let note = label(
            "仅普通听写成功粘贴后生效；翻译、闪念和 OpenClaw 不执行。",
            size: 11
        )
        note.textColor = UITheme.waterInkMuted
        note.maximumNumberOfLines = 0
        note.lineBreakMode = .byWordWrapping
        return rowStack([
            optionRow("粘贴后自动发送", autoSendAfterPaste),
            optionRow("发送倒计时", autoSendCountdownControl),
            optionRow("应用范围", autoSendApplicationScopeButton),
            note,
        ])
    }

    private func buildSystemSettingsContent() -> NSView {
        return rowStack([
            optionRow("开机自动启动", launchAtLogin),
            optionRow("启动动画", replayLaunchAnimationButton),
        ])
    }

    private func buildRecordingPreviewSettingsContent() -> NSView {
        shadowPreviewExperiment.toolTip = "诊断用：在主胶囊旁显示旁路结果；不参与最终识别和粘贴。"
        let productSettings = rowStack([
            optionRow("胶囊实时预览", realtime),
            optionRow("重叠矫正", correctedPreviewExperiment, showsLeader: true),
            optionRow("停顿自动完成", autoFinish),
            optionRow("停止后重新识别整段录音", reRecognizeWholeRecordingAfterStop),
            optionRow("录音时降低系统音量", duckSystemAudio),
            optionRow("录音时暂停媒体", pauseSystemMedia),
        ])
        let diagnostics = subSectionView("诊断工具（实验）", rowStack([
            optionRow("旁路预览（诊断）", shadowPreviewExperiment),
            optionRow("在线旁路（诊断）", onlineASRProviderMode),
            optionRow("豆包 Key", doubaoASRKeyButton),
            optionRow("MiMo Key", mimoASRKeyButton),
            onlineASRPrivacyNote,
        ]))
        let divider = hairlineView()
        let stack = NSStackView(views: [productSettings, divider, diagnostics])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.groupSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        [productSettings, divider, diagnostics].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func buildPrimaryMicrophoneContent() -> NSView {
        let audioInputControls = NSStackView(views: [audioInputDeviceMode, audioInputRefreshButton])
        audioInputControls.orientation = .horizontal
        audioInputControls.alignment = .centerY
        audioInputControls.spacing = 4
        audioInputStatus.textColor = UITheme.waterInkMuted
        let stack = NSStackView(views: [optionRow("主麦克风", audioInputControls), audioInputStatus])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func buildBluetoothMicPreferenceContent() -> NSView {
        let note = label("连接蓝牙耳机听声音时，若主麦克风仍是“跟随系统”，可优先用 Mac 内置麦克风收音；手动锁定的 USB / 耳机麦克风不会被覆盖。", size: 12)
        note.textColor = UITheme.waterInkMuted
        note.maximumNumberOfLines = 0
        note.lineBreakMode = .byWordWrapping
        return rowStack([
            optionRow("蓝牙耳机播放时使用 Mac 麦克风", preferBuiltInMicForBluetoothAudio),
            note,
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
            optionRow("整理模式", smartRewriteMode),
            optionRow("自动翻译", autoTranslate),
            optionRow("翻译方向", translationDirectionMode),
            optionRow("整理模型", smartAIModelMode),
            optionRow("闪念整理", ideaPillRewriteMode),
            optionRow("归档整理", screenshotArchiveMode),
            optionRow("应用范围", autoScopeButton),
            optionRow("整理提示词", promptSettingsButton),
            optionRow("开发术语", developerTermsButton),
            optionRow("翻译提示词", translationPromptButton),
            optionRow("社交清单", socialScopeButton),
            keyRow,
            usageRow,
        ])
    }

    private func buildModelTabSmartAIModelContent() -> NSView {
        let note = label("与智能页的“整理模型”是同一个设置；可在本地直驱 Qwen3 4B 与云端 DeepSeek 之间切换。", size: 12)
        note.textColor = UITheme.waterInkMuted
        note.maximumNumberOfLines = 0
        note.lineBreakMode = .byWordWrapping

        let actions = NSStackView(views: [
            localModelHealthCopyButton,
            localModelHealthCheckButton,
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        let result = NSStackView(views: [
            localModelHealthStatusLabel,
            localModelHealthDetailLabel,
        ])
        result.orientation = .vertical
        result.alignment = .leading
        result.spacing = 2
        result.translatesAutoresizingMaskIntoConstraints = false
        localModelHealthStatusLabel.widthAnchor.constraint(
            equalTo: result.widthAnchor
        ).isActive = true
        localModelHealthDetailLabel.widthAnchor.constraint(
            equalTo: result.widthAnchor
        ).isActive = true

        return rowStack([
            optionRow("整理模型", modelTabSmartAIModelMode),
            note,
            optionRow("本地模型检测", actions),
            result,
        ])
    }

    private func buildHotkeysPanelContent() -> NSView {
        return rowStack([
            shortcutRow(title: "主快捷键", captureButton: hotkeyCaptureButton, fallbackButton: hotkeyResetButton, mousePresetPicker: hotkeyMouseShortcutPicker),
            shortcutRow(title: "备用快捷键", captureButton: secondaryHotkeyCaptureButton, fallbackButton: secondaryHotkeyClearButton, mousePresetPicker: secondaryHotkeyMouseShortcutPicker),
            shortcutRow(title: "截图快捷键", captureButton: screenshotHotkeyCaptureButton, fallbackButton: screenshotHotkeyResetButton, mousePresetPicker: screenshotHotkeyMouseShortcutPicker),
            shortcutRow(title: "截图备用", captureButton: secondaryScreenshotHotkeyCaptureButton, fallbackButton: secondaryScreenshotHotkeyClearButton, mousePresetPicker: secondaryScreenshotHotkeyMouseShortcutPicker),
            shortcutRow(title: "翻译截图", captureButton: screenshotTranslationHotkeyCaptureButton, fallbackButton: screenshotTranslationHotkeyResetButton, mousePresetPicker: screenshotTranslationHotkeyMouseShortcutPicker),
            shortcutRow(title: "自动翻译", captureButton: autoTranslateHotkeyCaptureButton, fallbackButton: autoTranslateHotkeyClearButton, mousePresetPicker: autoTranslateHotkeyMouseShortcutPicker),
            shortcutRow(title: "唤起主页", captureButton: mainWindowHotkeyCaptureButton, fallbackButton: mainWindowHotkeyResetButton, mousePresetPicker: mainWindowHotkeyMouseShortcutPicker),
            shortcutRow(title: "OpenClaw", captureButton: openClawHotkeyPanelCaptureButton, fallbackButton: openClawHotkeyPanelResetButton, mousePresetPicker: openClawHotkeyPanelMouseShortcutPicker),
        ])
    }

    private func buildOpenClawPanelContent() -> NSView {
        configureOpenClawTextField(openClawGatewayField)
        configureOpenClawTextField(openClawAgentField)
        configureOpenClawTextField(openClawSessionField)
        configureOpenClawTextField(openClawCLIPathField)
        openClawStatusValue.textColor = UITheme.sectionTitle
        openClawCheckButton.bezelStyle = .rounded
        openClawCheckButton.controlSize = .regular
        openClawCheckButton.font = .systemFont(ofSize: 12, weight: .medium)
        openClawCheckButton.target = self
        openClawCheckButton.action = #selector(checkOpenClawConnection)

        let statusRow = NSStackView(views: [openClawStatusValue, openClawCheckButton])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        return rowStack([
            optionRow("连接状态", statusRow),
            shortcutRow(title: "激活键", captureButton: openClawHotkeyCaptureButton, fallbackButton: openClawHotkeyResetButton, mousePresetPicker: openClawHotkeyMouseShortcutPicker),
            optionRow("Gateway", openClawGatewayField),
            optionRow("Agent", openClawAgentField),
            optionRow("Session", openClawSessionField),
            optionRow("CLI 路径", openClawCLIPathField),
        ])
    }

    private func buildOpenClawVoicePanelContent() -> NSView {
        refreshOpenClawVoiceControls()
        let volumeControls = NSStackView(views: [openClawVoiceVolumeSlider, openClawVoiceVolumeValue])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 8
        let rateControls = NSStackView(views: [openClawVoiceRateSlider, openClawVoiceRateValue])
        rateControls.orientation = .horizontal
        rateControls.alignment = .centerY
        rateControls.spacing = 8

        return rowStack([
            optionRow("开启说话", openClawVoiceEnabledSwitch),
            optionRow("音量", volumeControls),
            optionRow("语速", rateControls),
            optionRow("音色", openClawVoiceMode),
            optionRow("播放内容", openClawVoicePlaybackMode),
            optionRow("打断策略", openClawVoiceInterruptMode),
        ])
    }

    func refreshOpenClawVoiceControls() {
        let voices = OpenClawVoiceSettings.availableVoices
        let availableVoiceIDs = Set(voices.map(\.id))
        let settings = OpenClawVoiceSettingsStore.standard.load(
            availableVoiceIDs: availableVoiceIDs
        )
        openClawVoiceEnabledSwitch.state = settings.enabled ? .on : .off
        openClawVoiceEnabledSwitch.target = self
        openClawVoiceEnabledSwitch.action = #selector(saveOpenClawVoiceSettingsFromUI)

        openClawVoiceMode.removeAllItems()
        for voice in voices {
            openClawVoiceMode.addItem(
                withTitle: voice.menuTitle
            )
            openClawVoiceMode.lastItem?.representedObject = voice.id
        }
        if let selectedIndex = openClawVoiceMode.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == settings.voiceID
        }) {
            openClawVoiceMode.selectItem(at: selectedIndex)
        }
        openClawVoiceMode.toolTip = "选择 OpenClaw 回复使用的 ZipVoice 音色"
        openClawVoiceMode.target = self
        openClawVoiceMode.action = #selector(saveOpenClawVoiceSettingsFromUI)
        configureVoicePopup(
            openClawVoicePlaybackMode,
            items: OpenClawVoicePlaybackPolicy.allCases,
            selected: settings.playbackPolicy,
            titleKeyPath: \.displayName,
            tooltip: "控制哪些 OpenClaw 内容会被朗读"
        )
        configureVoicePopup(
            openClawVoiceInterruptMode,
            items: OpenClawVoiceInterruptPolicy.allCases,
            selected: settings.interruptPolicy,
            titleKeyPath: \.displayName,
            tooltip: "控制新回复到来时如何处理正在播放的语音"
        )

        openClawVoiceVolumeSlider.doubleValue = settings.volume
        openClawVoiceVolumeSlider.isContinuous = true
        openClawVoiceVolumeSlider.target = self
        openClawVoiceVolumeSlider.action = #selector(saveOpenClawVoiceSettingsFromUI)
        openClawVoiceVolumeValue.textColor = UITheme.sectionTitle
        openClawVoiceVolumeValue.alignment = .right
        openClawVoiceRateSlider.doubleValue = settings.speechRate
        openClawVoiceRateSlider.isContinuous = true
        openClawVoiceRateSlider.target = self
        openClawVoiceRateSlider.action = #selector(saveOpenClawVoiceSettingsFromUI)
        openClawVoiceRateValue.textColor = UITheme.sectionTitle
        openClawVoiceRateValue.alignment = .right
        refreshOpenClawVoiceVolumeLabel()
        refreshOpenClawVoiceRateLabel()
    }

    private func configureVoicePopup<Item: RawRepresentable & Equatable>(
        _ popup: NSPopUpButton,
        items: [Item],
        selected: Item,
        titleKeyPath: KeyPath<Item, String>,
        tooltip: String
    ) where Item.RawValue == String {
        popup.removeAllItems()
        for item in items {
            popup.addItem(withTitle: item[keyPath: titleKeyPath])
            popup.lastItem?.representedObject = item.rawValue
        }
        let selectedItem = popup.itemArray.first { ($0.representedObject as? String) == selected.rawValue }
        popup.select(selectedItem)
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: 12, weight: .medium)
        popup.toolTip = tooltip
        popup.target = self
        popup.action = #selector(saveOpenClawVoiceSettingsFromUI)
    }

    private func configureOpenClawTextField(_ field: NSTextField) {
        field.bezelStyle = .roundedBezel
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.lineBreakMode = .byTruncatingMiddle
        field.target = self
        field.action = #selector(saveOpenClawSettingsFromUI)
    }

    // 快捷键录入按钮的接线与样式（原在偏好弹窗里，现由「快捷键」面板复用）
    func wireHotkeyButtons() {
        [hotkeyValue, secondaryHotkeyValue, screenshotHotkeyValue, secondaryScreenshotHotkeyValue,
         screenshotTranslationHotkeyValue, autoTranslateHotkeyValue, mainWindowHotkeyValue,
         ideaPillHotkeyValue, openClawHotkeyValue].forEach {
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
        ideaPillHotkeyCaptureButton.target = self; ideaPillHotkeyCaptureButton.action = #selector(beginIdeaPillHotkeyCapture)
        ideaPillHotkeyClearButton.target = self; ideaPillHotkeyClearButton.action = #selector(clearIdeaPillHotkey)
        openClawHotkeyCaptureButton.target = self; openClawHotkeyCaptureButton.action = #selector(beginOpenClawHotkeyCapture(_:))
        openClawHotkeyResetButton.target = self; openClawHotkeyResetButton.action = #selector(resetOpenClawHotkey)
        openClawHotkeyPanelCaptureButton.target = self; openClawHotkeyPanelCaptureButton.action = #selector(beginOpenClawHotkeyCapture(_:))
        openClawHotkeyPanelResetButton.target = self; openClawHotkeyPanelResetButton.action = #selector(resetOpenClawHotkey)
        configureHotkeyMouseShortcutPicker(hotkeyMouseShortcutPicker, slot: .primary, preferredCaptureButton: hotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(secondaryHotkeyMouseShortcutPicker, slot: .secondary, preferredCaptureButton: secondaryHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(screenshotHotkeyMouseShortcutPicker, slot: .screenshot, preferredCaptureButton: screenshotHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(secondaryScreenshotHotkeyMouseShortcutPicker, slot: .screenshotSecondary, preferredCaptureButton: secondaryScreenshotHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(screenshotTranslationHotkeyMouseShortcutPicker, slot: .screenshotTranslation, preferredCaptureButton: screenshotTranslationHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(autoTranslateHotkeyMouseShortcutPicker, slot: .autoTranslate, preferredCaptureButton: autoTranslateHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(mainWindowHotkeyMouseShortcutPicker, slot: .mainWindow, preferredCaptureButton: mainWindowHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(ideaPillHotkeyMouseShortcutPicker, slot: .ideaPill, preferredCaptureButton: ideaPillHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(openClawHotkeyMouseShortcutPicker, slot: .openClaw, preferredCaptureButton: openClawHotkeyCaptureButton)
        configureHotkeyMouseShortcutPicker(openClawHotkeyPanelMouseShortcutPicker, slot: .openClaw, preferredCaptureButton: openClawHotkeyPanelCaptureButton)
        let captureButtons = [hotkeyCaptureButton, secondaryHotkeyCaptureButton, screenshotHotkeyCaptureButton,
                              secondaryScreenshotHotkeyCaptureButton, screenshotTranslationHotkeyCaptureButton,
                              autoTranslateHotkeyCaptureButton, mainWindowHotkeyCaptureButton,
                              ideaPillHotkeyCaptureButton, openClawHotkeyCaptureButton,
                              openClawHotkeyPanelCaptureButton]
        let mouseShortcutPickers = [hotkeyMouseShortcutPicker, secondaryHotkeyMouseShortcutPicker,
                                    screenshotHotkeyMouseShortcutPicker, secondaryScreenshotHotkeyMouseShortcutPicker,
                                    screenshotTranslationHotkeyMouseShortcutPicker, autoTranslateHotkeyMouseShortcutPicker,
                                    mainWindowHotkeyMouseShortcutPicker, ideaPillHotkeyMouseShortcutPicker,
                                    openClawHotkeyMouseShortcutPicker, openClawHotkeyPanelMouseShortcutPicker]
        let trailingButtons = [hotkeyResetButton, secondaryHotkeyClearButton, screenshotHotkeyResetButton,
                               secondaryScreenshotHotkeyClearButton, screenshotTranslationHotkeyResetButton,
                               autoTranslateHotkeyClearButton, mainWindowHotkeyResetButton,
                               ideaPillHotkeyClearButton, openClawHotkeyResetButton,
                               openClawHotkeyPanelResetButton]
        (captureButtons + trailingButtons).forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
        }
        mouseShortcutPickers.forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
            $0.widthAnchor.constraint(equalToConstant: 74).isActive = true
        }
        captureButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 128).isActive = true }
        trailingButtons.forEach { $0.widthAnchor.constraint(equalToConstant: 70).isActive = true }
    }

    func configureHotkeyMouseShortcutPicker(
        _ popup: NSPopUpButton,
        slot: HotkeySlot,
        preferredCaptureButton: NSButton
    ) {
        popup.removeAllItems()
        popup.addItem(withTitle: "自定义")
        popup.lastItem?.tag = 0
        popup.addItem(withTitle: "第三键")
        popup.lastItem?.tag = 3
        popup.addItem(withTitle: "第四键")
        popup.lastItem?.tag = 4
        popup.addItem(withTitle: "第五键")
        popup.lastItem?.tag = 5
        popup.addItem(withTitle: "第六键")
        popup.lastItem?.tag = 6
        popup.tag = slot.rawValue
        popup.target = self
        popup.action = #selector(hotkeyMouseShortcutPickerChanged(_:))
        popup.toolTip = "选择“自定义”可录入快捷键，或直接绑定第三/四/五/六按钮"
        popup.itemArray.first?.title = "自定义"
    }
}
