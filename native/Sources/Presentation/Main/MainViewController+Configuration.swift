import AppKit

extension MainViewController {
    func configureOptionAccessibility() {
        smartRewriteMode.setAccessibilityLabel("智能整理")
        ideaPillRewriteMode.setAccessibilityLabel("闪念胶囊整理模式")
        smartAIModelMode.setAccessibilityLabel("智能整理模型")
        modelTabSmartAIModelMode.setAccessibilityLabel("模型页智能整理模型")
        localModelHealthCheckButton.setAccessibilityLabel("检测本地整理模型")
        localModelHealthCopyButton.setAccessibilityLabel("复制本地模型诊断")
        localModelHealthStatusLabel.setAccessibilityLabel("本地模型检测状态")
        localModelHealthDetailLabel.setAccessibilityLabel("本地模型检测详情")
        asrBackendMode.setAccessibilityLabel("识别模型")
        asrBackendMode.toolTip = "选择 final 识别使用的本地 ASR 后端"
        asrSwitchProgress.setAccessibilityLabel("识别模型切换进度")
        asrSwitchProgressLabel.setAccessibilityLabel("识别模型切换状态")
        deepSeekKeyButton.setAccessibilityLabel("DeepSeek API Key")
        promptSettingsButton.setAccessibilityLabel("智能整理提示词")
        autoScopeButton.setAccessibilityLabel("智能整理应用范围")
        autoSendAfterPaste.setAccessibilityLabel("粘贴后自动发送")
        autoSendCountdownSeconds.setAccessibilityLabel("自动发送倒计时")
        autoSendApplicationScopeButton.setAccessibilityLabel("自动发送应用范围")
        developerTermsButton.setAccessibilityLabel("开发术语词库")
        autoTranslate.setAccessibilityLabel("自动翻译")
        autoTranslate.toolTip = "可在快捷键设置中配置快速打开或关闭"
        ideaPillHotkeyCaptureButton.setAccessibilityLabel("闪念胶囊快捷键")
        openClawHotkeyCaptureButton.setAccessibilityLabel("OpenClaw 语音快捷键")
        openClawHotkeyPanelCaptureButton.setAccessibilityLabel("OpenClaw 快捷键")
        translationDirectionMode.setAccessibilityLabel("翻译方向")
        translationPromptButton.setAccessibilityLabel("翻译提示词")
        socialScopeButton.setAccessibilityLabel("社交应用清单")
        screenshotSaveLocationButton.setAccessibilityLabel("截图保存位置")
        screenshotArchiveMode.setAccessibilityLabel("截图归档整理模式")
        backlogDirectoryButton.setAccessibilityLabel("需求池目录")
        realtime.setAccessibilityLabel("胶囊实时预览")
        shadowPreviewExperiment.setAccessibilityLabel("旁路预览（诊断）")
        shadowPreviewExperiment.toolTip = "诊断用：在主胶囊旁显示旁路结果；不参与最终识别和粘贴。"
        onlineASRProviderMode.setAccessibilityLabel("在线旁路服务（诊断）")
        doubaoASRKeyButton.setAccessibilityLabel("豆包 API Key")
        mimoASRKeyButton.setAccessibilityLabel("MiMo API Key")
        correctedPreviewExperiment.setAccessibilityLabel("重叠矫正")
        correctedPreviewExperiment.toolTip = "使用跨分块音频矫正接缝；默认关闭，仅支持 SenseVoice。"
        longFormIncrementalOutputExperiment.setAccessibilityLabel("长录音增量输出（实验）")
        longFormIncrementalOutputExperiment.toolTip = "自动启用重叠校正；最长 4 小时，停止时使用增量转录而不是重识别整段音频。"
        autoFinish.setAccessibilityLabel("停顿自动完成")
        reRecognizeWholeRecordingAfterStop.setAccessibilityLabel("停止后重新识别整段录音")
        reRecognizeWholeRecordingAfterStop.toolTip = "SenseVoice 可直接使用完整实时缓存以获得更快结果；选择其他识别模型时，停止录音后会自动运行所选模型。所选模型失败时会直接提示失败，不会切换到 SenseVoice。"
        duckSystemAudio.setAccessibilityLabel("录音时降低系统音量")
        pauseSystemMedia.setAccessibilityLabel("录音时暂停媒体")
        pauseSystemMedia.toolTip = "录音开始时仅暂停正在播放的系统媒体；录音结束后只恢复本次暂停的内容。"
        audioInputDeviceMode.setAccessibilityLabel("麦克风输入设备")
        audioInputRefreshButton.setAccessibilityLabel("刷新麦克风输入设备")
        preferBuiltInMicForBluetoothAudio.setAccessibilityLabel("蓝牙耳机播放时使用 Mac 麦克风")
        preferBuiltInMicForBluetoothAudio.toolTip = "开启后，主麦克风为“跟随系统”且系统默认输入像蓝牙耳机时，录音会优先采集 Mac 内置麦克风；手动选择的麦克风不受影响。"
        launchAtLogin.setAccessibilityLabel("开机自动启动")
        openClawGatewayField.setAccessibilityLabel("OpenClaw Gateway 地址")
        openClawAgentField.setAccessibilityLabel("OpenClaw Agent")
        openClawSessionField.setAccessibilityLabel("OpenClaw Session")
        openClawCLIPathField.setAccessibilityLabel("OpenClaw CLI 路径")
        openClawVoiceEnabledSwitch.setAccessibilityLabel("小龙虾说话开关")
        openClawVoiceVolumeSlider.setAccessibilityLabel("小龙虾音量")
        openClawVoiceRateSlider.setAccessibilityLabel("小龙虾语速")
        openClawVoiceMode.setAccessibilityLabel("小龙虾朗读音色")
        openClawVoicePlaybackMode.setAccessibilityLabel("小龙虾播放内容")
        openClawVoiceInterruptMode.setAccessibilityLabel("小龙虾打断策略")
        ttsReadingLabView.textView.setAccessibilityLabel("朗读测试文字")
        ttsReadingLabView.modelPopup.setAccessibilityLabel("本地朗读模型")
        ttsReadingLabView.playButton.setAccessibilityLabel("播放或停止朗读测试")
        ttsReadingLabView.replayButton.setAccessibilityLabel("重播最近朗读音频")
    }

    func configureOnlineASRControls(settings: OnlineASRSettings) {
        onlineASRProviderMode.removeAllItems()
        for selection in OnlineASRProviderSelection.allCases {
            onlineASRProviderMode.addItem(withTitle: selection.displayName)
            onlineASRProviderMode.lastItem?.representedObject = selection.rawValue
        }
        if let index = OnlineASRProviderSelection.allCases.firstIndex(of: settings.selection) {
            onlineASRProviderMode.selectItem(at: index)
        }
        onlineASRProviderMode.bezelStyle = .rounded
        onlineASRProviderMode.controlSize = .small
        onlineASRProviderMode.font = .systemFont(ofSize: 11, weight: .medium)
        onlineASRProviderMode.target = self
        onlineASRProviderMode.action = #selector(saveOnlineASRSettings)
        onlineASRProviderMode.toolTip = "在线旁路：关闭 / 豆包 ASR / MiMo‑V2.5-ASR。选择只对下一轮录音生效。"

        [doubaoASRKeyButton, mimoASRKeyButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
        }
        doubaoASRKeyButton.target = self
        doubaoASRKeyButton.action = #selector(configureDoubaoASRKey)
        mimoASRKeyButton.target = self
        mimoASRKeyButton.action = #selector(configureMiMoASRKey)
        onlineASRPrivacyNote.font = .systemFont(ofSize: 11)
        onlineASRPrivacyNote.textColor = UITheme.waterInkMuted
        onlineASRPrivacyNote.maximumNumberOfLines = 2
        onlineASRPrivacyNote.lineBreakMode = .byWordWrapping
        onlineASRPrivacyNote.setAccessibilityLabel("在线旁路隐私说明")
        refreshOnlineASRCredentialButtons()
    }

    func refreshOnlineASRCredentialButtons() {
        let credentialStore = OnlineASRCredentialStore()
        doubaoASRKeyButton.title = credentialStore.has(.doubaoAPIKey) ? "已配置" : "未配置"
        mimoASRKeyButton.title = credentialStore.has(.mimoAPIKey) ? "已配置" : "未配置"
        doubaoASRKeyButton.toolTip = credentialStore.has(.doubaoAPIKey)
            ? "豆包 Key 已安全保存在 macOS Keychain；点击可覆盖或清除。"
            : "点击配置豆包 API Key。"
        mimoASRKeyButton.toolTip = credentialStore.has(.mimoAPIKey)
            ? "MiMo Key 已安全保存在 macOS Keychain；点击可覆盖或清除。"
            : "点击配置 MiMo API Key。"
    }

    func configureAudioInputDeviceControls(selectedUID: String) {
        audioInputDeviceMode.bezelStyle = .rounded
        audioInputDeviceMode.controlSize = .small
        audioInputDeviceMode.font = .systemFont(ofSize: 11, weight: .medium)
        audioInputDeviceMode.toolTip = "默认跟随系统输入；通话场景录不到音时可手动锁定正在使用的麦克风。"
        configureDeferredAudioInputDeviceMenu(selectedUID: selectedUID)
        audioInputDeviceMode.menu?.delegate = self

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

    private func configureDeferredAudioInputDeviceMenu(selectedUID: String) {
        audioInputDeviceMode.removeAllItems()
        if selectedUID.isEmpty {
            audioInputDeviceMode.addItem(withTitle: "跟随系统")
            audioInputDeviceMode.lastItem?.representedObject = AudioInputDevice.systemDefaultUID
            audioInputDeviceMode.toolTip = "录音时跟随 macOS 当前系统输入；点刷新可查看设备列表。"
            audioInputStatus.stringValue = "跟随 macOS 系统输入"
        } else {
            let selectedName = AudioInputDevice.selectedName
            audioInputDeviceMode.addItem(withTitle: selectedName.isEmpty ? "已选择麦克风" : selectedName)
            audioInputDeviceMode.lastItem?.representedObject = selectedUID
            audioInputDeviceMode.addItem(withTitle: "跟随系统")
            audioInputDeviceMode.lastItem?.representedObject = AudioInputDevice.systemDefaultUID
            audioInputDeviceMode.toolTip = "录音时会校验已选择麦克风；点刷新可查看当前设备列表。"
            audioInputStatus.stringValue = selectedName.isEmpty
                ? "已保存主麦克风，打开列表可确认连接状态"
                : "主麦克风：\(selectedName)"
        }
        audioInputDeviceMode.selectItem(at: 0)
        audioInputDeviceMenuHasLoaded = false
    }

    func refreshAudioInputDeviceMenu(selectedUID: String? = nil) {
        audioInputDeviceMenuHasLoaded = true
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
            audioInputStatus.stringValue = "设备已断开，已改为跟随系统"
        } else if resolvedUID.isEmpty {
            audioInputStatus.stringValue = "正在使用：\(defaultName)（跟随系统）"
        } else {
            audioInputStatus.stringValue = "正在使用：\(devices.first(where: { $0.uid == resolvedUID })?.name ?? "所选麦克风")"
        }
        selectAudioInputDeviceMenuItem(uid: resolvedUID)
        audioInputDeviceMode.toolTip = resolvedUID.isEmpty
            ? "跟随 macOS 当前系统输入：\(defaultName)"
            : "录音时锁定选中的麦克风；如果设备消失会自动回到跟随系统。"
        startAudioInputRouteObserver()
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
        guard audioInputDeviceMenuHasLoaded else { return }
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

    func configureIdeaPillRewriteModeMenu(_ preference: SmartRewritePreference) {
        ideaPillRewriteMode.removeAllItems()
        for item in IdeaPillRewriteModeStore.supportedModes {
            ideaPillRewriteMode.addItem(withTitle: item.displayName)
            ideaPillRewriteMode.lastItem?.representedObject = item.rawValue
        }
        let selected = IdeaPillRewriteModeStore.supportedModes.contains(preference)
            ? preference
            : IdeaPillRewriteModeStore.defaultMode
        let selectedItem = ideaPillRewriteMode.itemArray.first {
            ($0.representedObject as? String) == selected.rawValue
        }
        ideaPillRewriteMode.select(selectedItem)
        ideaPillRewriteMode.toolTip = "闪念胶囊录音完成后使用的整理模式，默认即时归纳"
        ideaPillRewriteMode.bezelStyle = .rounded
        ideaPillRewriteMode.controlSize = .regular
        ideaPillRewriteMode.font = .systemFont(ofSize: 12)
    }

    func configureSmartAIModelMenu(_ model: SmartAIModel) {
        configureSmartAIModelMenu(model, popup: smartAIModelMode)
        configureSmartAIModelMenu(model, popup: modelTabSmartAIModelMode)
    }

    func configureSmartAIModelMenu(_ model: SmartAIModel, popup: NSPopUpButton) {
        popup.removeAllItems()
        for item in SmartAIModel.allCases {
            popup.addItem(withTitle: item.displayName)
            popup.lastItem?.tag = item.menuTag
        }
        popup.selectItem(withTag: model.menuTag)
        popup.toolTip = "选择智能整理模型；语音翻译与截图翻译共用当前所选模型"
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: 12)
    }

    func configureLocalModelHealthCheckControls() {
        [localModelHealthCheckButton, localModelHealthCopyButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        localModelHealthCheckButton.target = self
        localModelHealthCheckButton.action = #selector(runLocalModelHealthCheck)
        localModelHealthCheckButton.toolTip = "实际检查运行环境、模型文件、模型加载与最小生成"

        localModelHealthCopyButton.target = self
        localModelHealthCopyButton.action = #selector(copyLocalModelHealthDiagnostic)
        localModelHealthCopyButton.toolTip = "复制不含录音、转录、提示词和密钥的诊断信息"
        localModelHealthCopyButton.isHidden = true
        localModelHealthCopyButton.isEnabled = false

        localModelHealthStatusLabel.textColor = UITheme.sectionTitle
        localModelHealthStatusLabel.maximumNumberOfLines = 2
        localModelHealthStatusLabel.lineBreakMode = .byWordWrapping
        localModelHealthDetailLabel.font = .systemFont(ofSize: 11)
        localModelHealthDetailLabel.textColor = UITheme.waterInkMuted
        localModelHealthDetailLabel.maximumNumberOfLines = 3
        localModelHealthDetailLabel.lineBreakMode = .byWordWrapping
    }

    func configureASRBackendMenu(_ backend: ASRBackend) {
        let items = ASRBackend.allCases.map { item -> ASRBackendSegmentedSelector.Item in
            let ready = isASRBackendReadyForSelection(item)
            let descriptor = liveASRModelRegistry.descriptor(for: item.candidateID)
            let title = ready ? item.displayName : "\(item.displayName)（不可用）"
            let reason: String
            switch descriptor?.readiness {
            case .unavailable(let message): reason = message
            case .validating: reason = "尚未通过真实转写验证"
            default: reason = ready ? "下一次录音使用此模型" : "模型或运行环境尚未就绪"
            }
            return .init(title:title,tag:item.menuTag,isEnabled:ready,toolTip:reason)
        }
        asrBackendMode.configure(items, selectedTag: backend.menuTag)
        asrBackendMode.toolTip = "SenseVoice 为默认稳定识别；全部模型按钮自动换行，可直接选择，当前录音不受中途切换影响"
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
        autoScopeButton.toolTip = "按应用设置默认整理模式，并管理通用高级规则"
    }

    func configureAutoSendControls() {
        let configuration = AutoSendSettingsStore.load()
        autoSendAfterPaste.state = configuration.isEnabled ? .on : .off
        autoSendAfterPaste.target = self
        autoSendAfterPaste.action = #selector(saveAutoSendEnabled)

        autoSendCountdownValueLabel.stringValue =
            "\(configuration.countdownSeconds) 秒"
        autoSendCountdownValueLabel.font = .systemFont(
            ofSize: 12,
            weight: .medium
        )
        autoSendCountdownValueLabel.textColor = UITheme.waterInkMuted
        autoSendCountdownValueLabel.alignment = .right
        autoSendCountdownValueLabel.widthAnchor.constraint(
            equalToConstant: 34
        ).isActive = true

        autoSendCountdownSeconds.minValue = 1
        autoSendCountdownSeconds.maxValue = 10
        autoSendCountdownSeconds.increment = 1
        autoSendCountdownSeconds.integerValue = configuration.countdownSeconds
        autoSendCountdownSeconds.valueWraps = false
        autoSendCountdownSeconds.target = self
        autoSendCountdownSeconds.action = #selector(
            saveAutoSendCountdownSeconds
        )
        autoSendCountdownSeconds.toolTip =
            "粘贴后等待 1–10 秒再发送；倒计时期间可取消"

        autoSendApplicationScopeButton.target = self
        autoSendApplicationScopeButton.action = #selector(
            configureAutoSendApplicationScope
        )
        autoSendApplicationScopeButton.bezelStyle = .rounded
        autoSendApplicationScopeButton.controlSize = .regular
        autoSendApplicationScopeButton.font = .systemFont(
            ofSize: 12,
            weight: .medium
        )
        autoSendApplicationScopeButton.toolTip =
            "为不同应用设置关闭、回车或 Command + 回车"
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

    func configureSocialScopeButton() {
        socialScopeButton.target = self
        socialScopeButton.action = #selector(configureSocialScope)
        socialScopeButton.bezelStyle = .rounded
        socialScopeButton.controlSize = .regular
        socialScopeButton.font = .systemFont(ofSize: 12, weight: .medium)
        socialScopeButton.toolTip = "维护社交窗口清单，命中时中译英使用社交提示词"
    }

    func configureScreenshotSaveLocationButton() {
        screenshotSaveLocationButton.target = self
        screenshotSaveLocationButton.action = #selector(configureScreenshotSaveLocation)
        screenshotSaveLocationButton.bezelStyle = .rounded
        screenshotSaveLocationButton.controlSize = .regular
        screenshotSaveLocationButton.font = .systemFont(ofSize: 12, weight: .medium)
        refreshScreenshotSaveLocationButton()
    }

    func configureScreenshotArchiveModeMenu(_ preference: SmartRewritePreference) {
        screenshotArchiveMode.removeAllItems()
        for item in ScreenshotArchiveModeStore.supportedModes {
            screenshotArchiveMode.addItem(withTitle: item.displayName)
            screenshotArchiveMode.lastItem?.tag = item.menuTag
        }
        let selected = ScreenshotArchiveModeStore.supportedModes.contains(preference)
            ? preference
            : ScreenshotArchiveModeStore.defaultMode
        screenshotArchiveMode.selectItem(withTag: selected.menuTag)
        screenshotArchiveMode.toolTip = "截图归档 OCR 后使用的智能整理模式"
        screenshotArchiveMode.bezelStyle = .rounded
        screenshotArchiveMode.controlSize = .regular
        screenshotArchiveMode.font = .systemFont(ofSize: 12, weight: .medium)
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
        deepSeekKeyButton.contentTintColor = hasKey ? UITheme.waterInkAccent : UITheme.waterInkMuted
        deepSeekKeyButton.toolTip = hasKey
            ? "DeepSeek API Key 已录入，点击可覆盖或清除"
            : "DeepSeek API Key 未录入，点击设置"
        deepSeekKeyButton.attributedTitle = NSAttributedString(
            string: "Key",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: hasKey ? .semibold : .medium),
                .foregroundColor: hasKey ? UITheme.waterInkAccent : UITheme.waterInkMuted,
            ]
        )
    }

    func refreshSmartAIUsageVisibility() {
        let usesDeepSeek = smartAIModel.provider == .deepSeek
        smartAIKeyRow?.isHidden = !usesDeepSeek
        smartAIUsageRow?.isHidden = !usesDeepSeek
        deepSeekBalanceButton.isHidden = !usesDeepSeek
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
        translationDirectionMode.toolTip = "自动翻译开启后使用的转换方向；多表情聊天模式会生成更轻松的英文聊天表达"
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
        if let image = NSImage(named: AppBrand.iconResourceName) {
            return image
        }
        if let url = Bundle.main.url(forResource: AppBrand.iconResourceName, withExtension: "icns") {
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

    @objc func showMouseShortcutTest(_ sender: NSButton) {
        if let popover = mouseShortcutTestPopover, popover.isShown {
            stopMouseShortcutTestMonitor()
            mouseShortcutTestPopover = nil
            popover.performClose(nil)
            return
        }

        stopMouseShortcutTestMonitor()
        mouseShortcutTestViewController.reset()
        mouseShortcutTestViewController.onClose = { [weak self] in
            self?.closeMouseShortcutTest()
        }

        let popover = mouseShortcutTestPopover ?? NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 190)
        popover.contentViewController = mouseShortcutTestViewController
        mouseShortcutTestPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        startMouseShortcutTestMonitor()
    }

    func closeMouseShortcutTest() {
        stopMouseShortcutTestMonitor()
        guard let popover = mouseShortcutTestPopover else { return }
        popover.performClose(nil)
        mouseShortcutTestPopover = nil
    }

    func startMouseShortcutTestMonitor() {
        stopMouseShortcutTestMonitor()
        NotificationCenter.default.post(
            name: .typeWhaleMouseShortcutHandlingSuspensionDidChange,
            object: true
        )
        mouseShortcutTestViewController.setStatus(
            "等待点击任意鼠标键。请先点击一次第 3/4/5/6 键。",
            detail: ""
        )
        mouseShortcutTestMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            let buttonNumber = Int(event.buttonNumber)
            let rawName = HotkeyKeyCodes.mouseDisplayName(for: buttonNumber)
            let mappedTags = self.compatibleHotkeyMouseTags(for: buttonNumber)
            let detail = mappedTags.isEmpty
                ? "当前事件未在第3~6按钮识别范围内。"
                : "TypeWhale 会把这个物理键当作：\(mappedTags.map { "第\($0)键" }.joined(separator: " / "))."
            self.mouseShortcutTestViewController.setStatus(
                "识别到按钮号: \(buttonNumber)（\(rawName)）",
                detail: detail
            )
        }
    }

    private func stopMouseShortcutTestMonitor() {
        NotificationCenter.default.post(
            name: .typeWhaleMouseShortcutHandlingSuspensionDidChange,
            object: false
        )
        if let monitor = mouseShortcutTestMonitor {
            NSEvent.removeMonitor(monitor)
            mouseShortcutTestMonitor = nil
        }
    }

    func compatibleMouseShortcutDisplayNames(for buttonNumber: Int) -> String {
        let compatibleTags = compatibleHotkeyMouseTags(for: buttonNumber)
        return compatibleTags.map { "第\($0)键" }.joined(separator: " / ")
    }

    func compatibleHotkeyMouseTags(for buttonNumber: Int) -> [Int] {
        var result = Set<Int>()
        switch buttonNumber {
        case 2:
            result.insert(3)
        case 3:
            result.insert(4)
        case 4:
            result.insert(5)
        case 5, 6, 7, 8:
            result.insert(6)
        default:
            break
        }
        return result.sorted()
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
            popover.contentSize = NSSize(width: 600, height: 326)
            popover.contentViewController = makeModelDetailController()
            modelDetailPopover = popover
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    func makeModelDetailController() -> NSViewController {
        let icon = symbolIcon("cpu", size: 18, color: UITheme.waterInkAccent)
        let title = label("本地 ASR 模型", size: 14, weight: .semibold)
        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping

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

        let stack = NSStackView(views: [titleRow, hairlineView(), modelValue, modelProgress, desc, pathCaption, modelPathLabel, installRow])
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

extension MainViewController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === audioInputDeviceMode.menu else { return }
        guard !audioInputDeviceMenuHasLoaded else { return }
        let selectedUID = selectedAudioInputDeviceUID
        refreshAudioInputDeviceMenu(selectedUID: selectedUID)
        LaunchDiagnostics.mark("audio_input_selection_refresh source=menu_will_open")
    }
}
