import AppKit

extension MainViewController {
    func configureOptionAccessibility() {
        smartRewriteMode.setAccessibilityLabel("智能整理")
        asrBackendMode.setAccessibilityLabel("识别模型")
        asrBackendMode.toolTip = "选择 final 识别使用的本地 ASR 后端"
        deepSeekKeyButton.setAccessibilityLabel("DeepSeek API Key")
        promptSettingsButton.setAccessibilityLabel("智能整理提示词")
        autoScopeButton.setAccessibilityLabel("智能整理自动范围")
        developerTermsButton.setAccessibilityLabel("开发术语词库")
        autoTranslate.setAccessibilityLabel("自动翻译")
        autoTranslate.toolTip = "可在快捷键设置中配置快速打开或关闭"
        translationDirectionMode.setAccessibilityLabel("翻译方向")
        translationPromptButton.setAccessibilityLabel("翻译提示词")
        screenshotSaveLocationButton.setAccessibilityLabel("截图保存位置")
        backlogDirectoryButton.setAccessibilityLabel("需求池目录")
        realtime.setAccessibilityLabel("胶囊实时预览")
        autoFinish.setAccessibilityLabel("停顿自动完成")
        duckSystemAudio.setAccessibilityLabel("录音时降低系统音量")
        audioInputDeviceMode.setAccessibilityLabel("麦克风输入设备")
        audioInputRefreshButton.setAccessibilityLabel("刷新麦克风输入设备")
        micNoiseReduction.setAccessibilityLabel("麦克风降噪（语音增强）")
        micNoiseReduction.toolTip = "开启 Apple 语音增强（回声消除+噪声抑制），嘈杂环境识别更稳；但会增加每次开始录音的延迟，建议仅在嘈杂时临时开启。默认关闭。"
        launchAtLogin.setAccessibilityLabel("开机自动启动")
    }

    func configureAudioInputDeviceControls(selectedUID: String) {
        audioInputDeviceMode.bezelStyle = .rounded
        audioInputDeviceMode.controlSize = .small
        audioInputDeviceMode.font = .systemFont(ofSize: 11, weight: .medium)
        audioInputDeviceMode.toolTip = "默认跟随系统输入；通话场景录不到音时可手动锁定正在使用的麦克风。"
        refreshAudioInputDeviceMenu(selectedUID: selectedUID)

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        audioInputRefreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新麦克风输入设备"
        )?.withSymbolConfiguration(config)
        audioInputRefreshButton.imagePosition = .imageOnly
        audioInputRefreshButton.imageScaling = .scaleProportionallyDown
        audioInputRefreshButton.bezelStyle = .rounded
        audioInputRefreshButton.controlSize = .small
        audioInputRefreshButton.toolTip = "刷新麦克风输入设备列表"
        audioInputRefreshButton.target = self
        audioInputRefreshButton.action = #selector(refreshAudioInputDevicesFromButton)
    }

    func refreshAudioInputDeviceMenu(selectedUID: String? = nil) {
        let targetUID = selectedUID ?? selectedAudioInputDeviceUID
        let defaultName = AudioInputDeviceProvider.defaultInputDeviceName() ?? "系统默认"
        let devices = AudioInputDeviceProvider.devices()
        audioInputDeviceMode.removeAllItems()

        audioInputDeviceMode.addItem(withTitle: "跟随系统（\(defaultName)）")
        audioInputDeviceMode.lastItem?.representedObject = AudioInputDevice.systemDefaultUID

        for device in devices {
            let suffix = device.isDefault ? " · 当前系统" : ""
            audioInputDeviceMode.addItem(withTitle: "\(device.name)\(suffix)")
            audioInputDeviceMode.lastItem?.representedObject = device.uid
        }

        let hasTarget = devices.contains { $0.uid == targetUID }
        let resolvedUID = targetUID.isEmpty || hasTarget ? targetUID : AudioInputDevice.systemDefaultUID
        if !targetUID.isEmpty, !hasTarget {
            AudioInputDevice.saveSelectedUID(AudioInputDevice.systemDefaultUID)
            detail.stringValue = "已找不到上次选择的麦克风，已回到跟随系统。"
            LaunchDiagnostics.mark("audio_input_selection_downgrade reason=device_missing selected_uid=\(targetUID)")
        }
        selectAudioInputDeviceMenuItem(uid: resolvedUID)
        audioInputDeviceMode.toolTip = resolvedUID.isEmpty
            ? "跟随 macOS 当前系统输入：\(defaultName)"
            : "录音时锁定选中的麦克风；如果设备消失会自动回到跟随系统。"
    }

    func selectAudioInputDeviceMenuItem(uid: String) {
        for item in audioInputDeviceMode.itemArray {
            if (item.representedObject as? String) == uid {
                audioInputDeviceMode.select(item)
                return
            }
        }
        audioInputDeviceMode.selectItem(at: 0)
    }

    @objc func refreshAudioInputDevicesFromButton() {
        refreshAudioInputDeviceMenu()
        detail.stringValue = "麦克风输入设备列表已刷新"
        LaunchDiagnostics.mark("audio_input_selection_refresh source=button")
    }

    func startAudioInputRouteObserver() {
        guard audioInputRouteObserver == nil else { return }
        let observer = AudioInputRouteObserver { [weak self] reason in
            self?.refreshAudioInputDevicesAfterRouteChange(reason)
        }
        observer.start()
        audioInputRouteObserver = observer
    }

    func refreshAudioInputDevicesAfterRouteChange(_ reason: AudioInputRouteChangeReason) {
        refreshAudioInputDeviceMenu()
        LaunchDiagnostics.mark("audio_input_selection_refresh source=route_change reason=\(reason.logName)")
    }

    func configureSmartRewriteModeMenu(_ preference: SmartRewritePreference) {
        smartRewriteMode.removeAllItems()
        for item in SmartRewritePreference.allCases {
            smartRewriteMode.addItem(withTitle: item.displayName)
            smartRewriteMode.lastItem?.tag = item.menuTag
        }
        smartRewriteMode.selectItem(withTag: preference.menuTag)
        smartRewriteMode.toolTip = "最终识别后、粘贴前的文本整理模式"
        smartRewriteMode.bezelStyle = .rounded
        smartRewriteMode.controlSize = .regular
        smartRewriteMode.font = .systemFont(ofSize: 12)
    }

    func configureASRBackendMenu(_ backend: ASRBackend) {
        asrBackendMode.removeAllItems()
        for item in ASRBackend.allCases {
            asrBackendMode.addItem(withTitle: item.displayName)
            asrBackendMode.lastItem?.tag = item.menuTag
        }
        asrBackendMode.selectItem(withTag: backend.menuTag)
        asrBackendMode.toolTip = "自动模式优先使用已安装的 Qwen3-ASR，否则回退 SenseVoice"
        asrBackendMode.bezelStyle = .rounded
        asrBackendMode.controlSize = .regular
        asrBackendMode.font = .systemFont(ofSize: 12)
    }

    func configureDeepSeekKeyButton() {
        deepSeekKeyButton.target = self
        deepSeekKeyButton.action = #selector(configureDeepSeekAPIKey)
        deepSeekKeyButton.bezelStyle = .rounded
        deepSeekKeyButton.controlSize = .regular
        deepSeekKeyButton.font = .systemFont(ofSize: 12, weight: .medium)
        deepSeekKeyButton.toolTip = "录入 DeepSeek API Key，保存到 macOS Keychain"
        deepSeekBalanceButton.target = self
        deepSeekBalanceButton.action = #selector(showDeepSeekBalance)
        deepSeekBalanceButton.bezelStyle = .circular
        deepSeekBalanceButton.controlSize = .small
        deepSeekBalanceButton.font = .systemFont(ofSize: 12, weight: .bold)
        deepSeekBalanceButton.toolTip = "查看 DeepSeek 实时余额和 TypeWhale 本机估算消费"
        refreshDeepSeekKeyButton()
    }

    func configurePromptSettingsButton() {
        promptSettingsButton.target = self
        promptSettingsButton.action = #selector(configureSmartRewritePrompts)
        promptSettingsButton.bezelStyle = .rounded
        promptSettingsButton.controlSize = .regular
        promptSettingsButton.font = .systemFont(ofSize: 12, weight: .medium)
        promptSettingsButton.toolTip = "调整、修改并保存智能整理提示词"
    }

    func configureAutoScopeButton() {
        autoScopeButton.target = self
        autoScopeButton.action = #selector(configureSmartRewriteAutoRules)
        autoScopeButton.bezelStyle = .rounded
        autoScopeButton.controlSize = .regular
        autoScopeButton.font = .systemFont(ofSize: 12, weight: .medium)
        autoScopeButton.toolTip = "设置自动模式在不同窗口中使用的整理模式"
    }

    func configureDeveloperTermsButton() {
        developerTermsButton.target = self
        developerTermsButton.action = #selector(configureDeveloperTerms)
        developerTermsButton.bezelStyle = .rounded
        developerTermsButton.controlSize = .regular
        developerTermsButton.font = .systemFont(ofSize: 12, weight: .medium)
        developerTermsButton.toolTip = "管理开发术语和别名"
    }

    func configureTranslationPromptButton() {
        translationPromptButton.target = self
        translationPromptButton.action = #selector(configureTranslationPrompts)
        translationPromptButton.bezelStyle = .rounded
        translationPromptButton.controlSize = .regular
        translationPromptButton.font = .systemFont(ofSize: 12, weight: .medium)
        translationPromptButton.toolTip = "调整、修改并保存自动翻译提示词"
    }

    func configureScreenshotSaveLocationButton() {
        screenshotSaveLocationButton.target = self
        screenshotSaveLocationButton.action = #selector(configureScreenshotSaveLocation)
        screenshotSaveLocationButton.bezelStyle = .rounded
        screenshotSaveLocationButton.controlSize = .regular
        screenshotSaveLocationButton.font = .systemFont(ofSize: 12, weight: .medium)
        refreshScreenshotSaveLocationButton()
    }

    func configureBacklogDirectoryButton() {
        backlogDirectoryButton.target = self
        backlogDirectoryButton.action = #selector(configureBacklogDirectory)
        backlogDirectoryButton.bezelStyle = .rounded
        backlogDirectoryButton.controlSize = .small
        backlogDirectoryButton.font = .systemFont(ofSize: 11, weight: .medium)
        refreshBacklogDirectoryButton()
    }

    func refreshScreenshotSaveLocationButton() {
        screenshotSaveLocationButton.title = ScreenshotSaveLocationStore.displayName
        screenshotSaveLocationButton.toolTip = "当前保存到：\(ScreenshotSaveLocationStore.directory.path)"
    }

    func refreshBacklogDirectoryButton() {
        backlogDirectoryButton.title = BacklogDirectoryStore.displayName
        backlogDirectoryButton.toolTip = "当前需求池目录：\(BacklogDirectoryStore.directory.path)"
    }

    func refreshDeepSeekKeyButton() {
        let hasKey = DeepSeekAPIKeyStore.hasAPIKey()
        deepSeekKeyButton.title = "Key"
        deepSeekKeyButton.contentTintColor = hasKey ? UITheme.brandYellow : .secondaryLabelColor
        deepSeekKeyButton.toolTip = hasKey
            ? "DeepSeek API Key 已录入，点击可覆盖或清除"
            : "DeepSeek API Key 未录入，点击设置"
        deepSeekKeyButton.attributedTitle = NSAttributedString(
            string: "Key",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: hasKey ? .semibold : .medium),
                .foregroundColor: hasKey ? UITheme.brandYellow : NSColor.secondaryLabelColor,
            ]
        )
    }

    func refreshSmartAIUsageVisibility() {
        smartAIUsageRow?.isHidden = false
        deepSeekBalanceButton.isHidden = false
    }

    func toggleAutoTranslateFromShortcut() {
        autoTranslate.state = autoTranslate.state == .on ? .off : .on
        autoTranslate.needsDisplay = true
        saveSettings()
        let stateText = autoTranslate.state == .on ? "已开启" : "已关闭"
        detail.stringValue = "自动翻译\(stateText) · Shift + \\"
    }

    func configureTranslationDirectionMenu(_ direction: SmartTranslationDirection) {
        translationDirectionMode.removeAllItems()
        for item in SmartTranslationDirection.allCases {
            translationDirectionMode.addItem(withTitle: item.displayName)
            translationDirectionMode.lastItem?.tag = item.menuTag
        }
        translationDirectionMode.selectItem(withTag: direction.menuTag)
        translationDirectionMode.toolTip = "自动翻译开启后使用的转换方向"
        translationDirectionMode.bezelStyle = .rounded
        translationDirectionMode.controlSize = .regular
        translationDirectionMode.font = .systemFont(ofSize: 12)
    }

    func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.42"
        let build = info?["CFBundleVersion"] as? String ?? "199"
        return "Version \(version) (\(build))"
    }

    func loadBrandIcon() -> NSImage? {
        guard let image = loadAppIcon() else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let unit: CGFloat = 1024
        let cropRect = CGRect(
            x: CGFloat(cgImage.width) * 148 / unit,
            y: CGFloat(cgImage.height) * 143 / unit,
            width: CGFloat(cgImage.width) * 728 / unit,
            height: CGFloat(cgImage.height) * 728 / unit
        ).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: brandIconVisibleSize, height: brandIconVisibleSize))
    }

    func loadAppIcon() -> NSImage? {
        if let image = NSImage(named: "TypeWhale") {
            return image
        }
        if let url = Bundle.main.url(forResource: "TypeWhale", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    @objc func showUsageGuide(_ sender: NSButton) {
        if let popover = usageGuidePopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = usageGuidePopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 184)
        popover.contentViewController = makeUsageGuideController()
        usageGuidePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    func makeUsageGuideController() -> NSViewController {
        let title = label("使用方法", size: 14, weight: .semibold)
        let body = label(
            """
            先开启麦克风和辅助功能。
            按 Fn 开始录音，再按一次或松开结束。
            首次打开测试版：右键 App 选“打开”；若被拦截，到 系统设置 > 隐私与安全性，点“仍要打开”。
            """,
            size: 12
        )
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 0

        let stack = NSStackView(views: [title, hairlineView(), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 184))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])

        let controller = NSViewController()
        controller.view = content
        return controller
    }

    @objc func showVersionHistory(_ sender: NSButton) {
        if let popover = versionHistoryPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = versionHistoryPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 390)
        popover.contentViewController = versionHistoryViewController
        versionHistoryPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc func showTestLogs(_ sender: NSButton) {
        if let popover = testLogsPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        testLogsViewController.reload()
        let popover = testLogsPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 430)
        popover.contentViewController = testLogsViewController
        testLogsPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc func showModelDetail(_ sender: NSGestureRecognizer) {
        guard let anchor = sender.view else { return }
        if let popover = modelDetailPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = modelDetailPopover ?? NSPopover()
        if modelDetailPopover == nil {
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 300, height: 282)
            popover.contentViewController = makeModelDetailController()
            modelDetailPopover = popover
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    func makeModelDetailController() -> NSViewController {
        let icon = symbolIcon("cpu", size: 18, color: UITheme.brandYellow)
        let title = label("本地 ASR 模型", size: 14, weight: .semibold)
        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping

        let backendCaption = label("识别模型", size: 11, weight: .medium)
        backendCaption.textColor = UITheme.sectionTitle
        asrBackendMode.setContentHuggingPriority(.required, for: .horizontal)
        asrBackendMode.widthAnchor.constraint(equalToConstant: 154).isActive = true
        let backendRow = NSStackView(views: [backendCaption, flexSpacer(), asrBackendMode])
        backendRow.orientation = .horizontal
        backendRow.alignment = .centerY
        backendRow.spacing = 10

        let desc = label("本地离线语音识别模型，全程在本机推理，不上传音频。Qwen3-ASR 使用原生 sherpa-onnx 链路。", size: 12)
        desc.textColor = .secondaryLabelColor
        desc.maximumNumberOfLines = 0
        desc.lineBreakMode = .byWordWrapping

        let pathCaption = label("模型位置", size: 11, weight: .medium)
        pathCaption.textColor = UITheme.sectionTitle
        modelPathLabel.textColor = .secondaryLabelColor
        modelPathLabel.maximumNumberOfLines = 3
        modelPathLabel.lineBreakMode = .byCharWrapping

        modelProgress.isIndeterminate = false
        modelProgress.minValue = 0
        modelProgress.maxValue = 1
        modelProgress.controlSize = .small
        modelProgress.isHidden = true
        modelInstallButton.target = self
        modelInstallButton.action = #selector(installModel)
        modelInstallButton.isHidden = true
        modelInstallButton.bezelStyle = .rounded
        let installRow = NSStackView(views: [flexSpacer(), modelInstallButton])
        installRow.orientation = .horizontal

        let stack = NSStackView(views: [titleRow, hairlineView(), backendRow, modelValue, modelProgress, desc, pathCaption, modelPathLabel, installRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 282))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 268),
            modelValue.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backendRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelPathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            installRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let controller = NSViewController()
        controller.view = content
        return controller
    }
}
