import AppKit

extension MainViewController {
    @objc func showASRBenchmark() { onShowASRBenchmark?() }

    @objc func requestFullAppExit(_ sender: NSButton) {
        onRequestFullAppExit?()
    }

    func configureReplayLaunchAnimationButton() {
        replayLaunchAnimationButton.bezelStyle = .rounded
        replayLaunchAnimationButton.controlSize = .regular
        replayLaunchAnimationButton.font = .systemFont(ofSize: 12, weight: .medium)
        replayLaunchAnimationButton.target = self
        replayLaunchAnimationButton.action = #selector(replayLaunchAnimation)
        replayLaunchAnimationButton.toolTip = "全屏重播水墨灰鲸启动动画"
    }

    @objc func replayLaunchAnimation() {
        LaunchAnimationPresenter.shared.replayFromSettings()
    }

    @objc func selectSmartAIModel() {
        smartAIModelSelectionGeneration = UUID()
        saveSettings()
    }

    @objc func saveSettings() {
        let previousASRBackend = activeASRBackend
        let requestedASRBackend = asrBackend
        let effectiveASRBackend = isASRBackendReadyForSelection(requestedASRBackend)
            ? requestedASRBackend
            : previousASRBackend
        let previousAudioInputUID = AppSettingsStore.loadMainViewSettings().audioInputDeviceUID
        let nextAudioInputUID = selectedAudioInputDeviceUID
        let previousSmartAIModel = SmartAIModelStore.load()
        let nextSmartAIModel = smartAIModel
        AppSettingsStore.save(MainViewSettings(
            realtimePreviewEnabled: realtime.state == .on,
            autoFinishAfterPauseEnabled: autoFinish.state == .on,
            duckSystemAudioWhileRecordingEnabled: duckSystemAudio.state == .on,
            pauseSystemMediaWhileRecordingEnabled: pauseSystemMedia.state == .on,
            reRecognizeWholeRecordingAfterStop: reRecognizeWholeRecordingAfterStop.state == .on,
            audioInputDeviceUID: selectedAudioInputDeviceUID,
            preferBuiltInMicForBluetoothAudio: preferBuiltInMicForBluetoothAudio.state == .on,
            asrBackend: previousASRBackend,
            smartRewritePreference: smartRewritePreference,
            autoTranslateEnabled: autoTranslate.state == .on,
            translationDirection: translationDirection,
            previewTheme: selectedPreviewTheme
        ))
        normalizeExperimentalPreviewSettings(persist: true, restoreSavedPreference: true)
        ScreenshotArchiveModeStore.save(screenshotArchivePreference)
        IdeaPillRewriteModeStore.save(ideaPillRewritePreference)
        if previousSmartAIModel != nextSmartAIModel {
            if nextSmartAIModel == .typeWhaleQwen3_4BInstruct {
                validateAndSelectQwen(previousModel: previousSmartAIModel)
            } else {
                applySmartAIModelSelection(nextSmartAIModel)
            }
        } else {
            syncSmartAIModelMenus(to: nextSmartAIModel)
        }
        if previousAudioInputUID != nextAudioInputUID {
            let mode = nextAudioInputUID.isEmpty ? "system_default" : "manual"
            LaunchDiagnostics.mark("audio_input_selection_save mode=\(mode) uid=\(nextAudioInputUID)")
            detail.stringValue = nextAudioInputUID.isEmpty
                ? "麦克风输入已改为跟随系统"
                : "麦克风输入已锁定为：\(audioInputDeviceMode.titleOfSelectedItem ?? "手动选择")"
        }
        if previousASRBackend != effectiveASRBackend {
            scheduleASRBackendChange(effectiveASRBackend, previousBackend: previousASRBackend)
        } else if requestedASRBackend != effectiveASRBackend {
            asrBackendMode.select(tag: effectiveASRBackend.menuTag)
            pendingASRBackendChangeWorkItem?.cancel()
            pendingASRBackendChangeWorkItem = nil
            cancelASRBackendSwitchProgress()
            LaunchDiagnostics.mark("asr_backend_selection_deferred backend=\(requestedASRBackend.rawValue)")
            detail.stringValue = "\(requestedASRBackend.displayName) 尚未就绪，当前正式识别链路保持不变"
        }
        refreshSmartAIUsageVisibility()
        if asrSwitchTarget == nil { refreshDisplayedModelState() }
        refreshPreviewThemeTiles()
    }

    func validateAndSelectQwen(previousModel: SmartAIModel) {
        let generation = smartAIModelSelectionGeneration
        syncSmartAIModelMenus(to: previousModel)
        detail.stringValue = "正在校验 Qwen3 4B 本地模型…"

        let service = ManagedLLMRuntimeService.shared
        switch service.runtimeState {
        case .ready:
            break
        case .missing:
            detail.stringValue = "Qwen3 4B 无法启用：TypeWhale 本地运行环境尚未安装"
            return
        case .invalid(let message):
            detail.stringValue = "Qwen3 4B 无法启用：\(message)"
            return
        }

        let registry = service.registry
        let runtimeLocator = service.runtimeLocator
        Task { [weak self] in
            let runtimeProbe = await Task.detached(priority: .utility) {
                runtimeLocator.probe()
            }.value
            guard let self,
                  self.smartAIModelSelectionGeneration == generation else { return }
            guard runtimeProbe.isReady else {
                self.syncSmartAIModelMenus(to: previousModel)
                self.detail.stringValue =
                    "Qwen3 4B 无法启用：\(runtimeProbe.userMessage ?? "本地运行环境校验失败")；当前模型保持为：\(previousModel.displayName)"
                return
            }

            let readiness = await Task.detached(priority: .utility) {
                registry.readiness(for: .qwen3_4BInstruct2507_4bit)
            }.value
            guard self.smartAIModelSelectionGeneration == generation else { return }
            switch readiness {
            case .ready:
                self.applySmartAIModelSelection(
                    .typeWhaleQwen3_4BInstruct
                )
                self.detail.stringValue = "已切换到本地直驱 Qwen3 4B，正在后台预热"
            case .missing:
                self.syncSmartAIModelMenus(to: previousModel)
                self.detail.stringValue = "Qwen3 4B 模型未安装，当前模型保持为：\(previousModel.displayName)"
            case .invalid(let reason):
                self.syncSmartAIModelMenus(to: previousModel)
                self.detail.stringValue = "Qwen3 4B 校验失败：\(reason)"
            }
        }
    }

    func applySmartAIModelSelection(_ model: SmartAIModel) {
        SmartAIModelStore.save(model)
        syncSmartAIModelMenus(to: model)
        LaunchDiagnostics.mark(
            "smart_ai_model_save provider=\(model.provider.rawValue) model=\(model.rawValue)"
        )
        detail.stringValue = "智能整理模型已切换为：\(model.displayName)"
        onSmartAIModelChange?(model)
    }

    func syncSmartAIModelMenus(to model: SmartAIModel) {
        smartAIModelMode.selectItem(withTag: model.menuTag)
        modelTabSmartAIModelMode.selectItem(withTag: model.menuTag)
    }

    @objc func selectPrimaryMicrophone() {
        if !selectedAudioInputDeviceUID.isEmpty {
            let name = (audioInputDeviceMode.titleOfSelectedItem ?? "")
                .replacingOccurrences(of: " · 当前系统", with: "")
            AudioInputDevice.saveSelectedName(name)
        }
        saveSettings()
        audioInputStatus.stringValue = "正在切换麦克风…"
        onPrimaryMicrophoneSelection?(selectedAudioInputDeviceUID)
    }

    @objc func saveOpenClawSettingsFromUI() {
        OpenClawSettingsStore.save(openClawSettings)
        openClawStatusValue.stringValue = "设置已保存"
        openClawStatusValue.textColor = UITheme.sectionTitle
        detail.stringValue = "OpenClaw 设置已保存"
        LaunchDiagnostics.mark("openclaw_settings_save agent=\(openClawSettings.agentID) session=\(openClawSettings.sessionKey)")
    }

    @objc func saveOpenClawVoiceSettingsFromUI() {
        let settings = openClawVoiceSettings.normalized
        OpenClawVoiceSettingsStore.standard.save(settings)
        openClawVoiceVolumeSlider.doubleValue = settings.volume
        openClawVoiceRateSlider.doubleValue = settings.speechRate
        refreshOpenClawVoiceVolumeLabel()
        refreshOpenClawVoiceRateLabel()
        detail.stringValue = settings.enabled ? "小龙虾声音设置已保存" : "小龙虾说话已关闭"
        LaunchDiagnostics.mark(
            "openclaw_voice_settings_save enabled=\(settings.enabled) voice=\(settings.voiceID) volume=\(settings.volume) rate=\(settings.speechRate) playback=\(settings.playbackPolicy.rawValue) interrupt=\(settings.interruptPolicy.rawValue)"
        )
    }

    func refreshOpenClawVoiceVolumeLabel() {
        openClawVoiceVolumeValue.stringValue = "\(Int(round(openClawVoiceVolumeSlider.doubleValue * 100)))%"
    }

    func refreshOpenClawVoiceRateLabel() {
        openClawVoiceRateValue.stringValue = String(format: "%.2fx", openClawVoiceRateSlider.doubleValue)
    }

    @objc func checkOpenClawConnection() {
        saveOpenClawSettingsFromUI()
        runOpenClawConnectionCheck(source: "manual_button", updateDetail: true)
    }

    func refreshOpenClawConnectionOnMainWindowOpen() {
        runOpenClawConnectionCheck(source: "main_window_open", updateDetail: false)
    }

    private func runOpenClawConnectionCheck(source: String, updateDetail: Bool) {
        guard !openClawConnectionCheckInFlight else {
            LaunchDiagnostics.mark("openclaw_health_skip source=\(source) reason=in_flight")
            return
        }
        openClawConnectionCheckInFlight = true
        openClawStatusValue.stringValue = "检测中"
        openClawStatusValue.textColor = UITheme.sectionTitle
        openClawCheckButton.isEnabled = false
        let settings = openClawSettings
        Task { [weak self] in
            do {
                _ = try await OpenClawCommandClient().health(settings: settings)
                await MainActor.run {
                    self?.openClawConnectionCheckInFlight = false
                    self?.openClawStatusValue.stringValue = "本机 Gateway 可用"
                    self?.openClawStatusValue.textColor = UITheme.healthGreen
                    self?.openClawCheckButton.isEnabled = true
                    if updateDetail {
                        self?.detail.stringValue = "OpenClaw Gateway 已连接"
                    }
                    LaunchDiagnostics.mark("openclaw_health_ok source=\(source) gateway=\(settings.gatewayURL)")
                }
            } catch {
                await MainActor.run {
                    self?.openClawConnectionCheckInFlight = false
                    self?.openClawStatusValue.stringValue = "连接失败"
                    self?.openClawStatusValue.textColor = .systemRed
                    self?.openClawCheckButton.isEnabled = true
                    if updateDetail {
                        self?.detail.stringValue = error.localizedDescription
                    }
                    LaunchDiagnostics.mark("openclaw_health_failed source=\(source) error=\"\(error.localizedDescription)\"")
                }
            }
        }
    }

    @objc func configureSmartRewritePrompts() {
        guard let window = view.window else { return }
        let dialog = SmartRewritePromptDialog(initialMode: smartRewritePreference.manualMode ?? .developerRequirement)
        dialog.present(in: window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .save(let mode, let template):
                SmartRewritePromptStore.save(template, for: mode)
                self.detail.stringValue = "\(mode.displayName)提示词已保存"
            case .reset(let mode):
                SmartRewritePromptStore.reset(mode)
                self.detail.stringValue = "\(mode.displayName)提示词已恢复默认"
            case .cancel:
                break
            }
        }
    }

    @objc func configureSmartRewriteAutoRules() {
        presentApplicationScope(initialSection: .rewrite)
    }

    @objc func configureAutoSendApplicationScope() {
        presentApplicationScope(initialSection: .autoSend)
    }

    @objc func saveAutoSendEnabled() {
        var configuration = AutoSendSettingsStore.load()
        configuration.isEnabled = autoSendAfterPaste.state == .on
        AutoSendSettingsStore.save(configuration)
        detail.stringValue = configuration.isEnabled
            ? "粘贴后自动发送已开启"
            : "粘贴后自动发送已关闭"
    }

    @objc func saveAutoSendCountdownSeconds() {
        let seconds = AutoSendConfiguration.normalizedCountdownSeconds(
            autoSendCountdownSeconds.integerValue
        )
        autoSendCountdownSeconds.integerValue = seconds
        autoSendCountdownValueLabel.stringValue = "\(seconds) 秒"
        var configuration = AutoSendSettingsStore.load()
        configuration.countdownSeconds = seconds
        AutoSendSettingsStore.save(configuration)
        detail.stringValue = "自动发送倒计时已设为 \(seconds) 秒"
    }

    private func presentApplicationScope(
        initialSection: ApplicationScopeSection
    ) {
        guard let window = view.window else { return }
        let catalog = ApplicationCatalog()
        let draft = ApplicationScopeDraft(
            rewriteConfiguration: SmartRewriteAutoRuleStore.load(),
            autoSendConfiguration: AutoSendSettingsStore.load()
        )
        let editorModel = ApplicationScopeEditorModel(
            initialSection: initialSection,
            draft: draft
        ) { [weak self] updated in
            SmartRewriteAutoRuleStore.save(updated.rewriteConfiguration)
            AutoSendSettingsStore.save(updated.autoSendConfiguration)
            self?.autoSendAfterPaste.state =
                updated.autoSendConfiguration.isEnabled ? .on : .off
            self?.detail.stringValue = "应用范围已保存"
        }
        let contentController = ApplicationScopeViewController(
            editorModel: editorModel,
            catalog: catalog
        )
        let windowController = ApplicationScopeWindowController(
            editorModel: editorModel,
            cancelCatalogLoading: { contentController.cancelLoading() }
        )
        windowController.setContentViewController(contentController)
        contentController.summaryDidChange = { [weak windowController] text in
            windowController?.setSummaryText(text)
        }
        windowController.present(in: window) { [weak contentController] section in
            contentController?.setSection(section)
        }
    }

    @objc func configureTranslationPrompts() {
        guard let window = view.window else { return }
        let dialog = SmartTranslationPromptDialog(initialDirection: translationDirection)
        dialog.present(in: window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .save(let direction, let social, let template):
                SmartTranslationPromptStore.save(template, for: direction, social: social)
                let label = social ? "中译英（社交）" : direction.displayName
                self.detail.stringValue = "\(label)提示词已保存"
            case .reset(let direction, let social):
                SmartTranslationPromptStore.reset(direction, social: social)
                let label = social ? "中译英（社交）" : direction.displayName
                self.detail.stringValue = "\(label)提示词已恢复默认"
            case .cancel:
                break
            }
        }
    }

    @objc func configureSocialScope() {
        guard let window = view.window else { return }
        SocialScopeDialog().present(in: window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .save(let raw):
                SmartTranslationSocialScopeStore.save(raw)
                self.detail.stringValue = "社交应用清单已保存"
            case .reset:
                SmartTranslationSocialScopeStore.reset()
                self.detail.stringValue = "社交应用清单已恢复默认"
            case .cancel:
                break
            }
        }
    }

    @objc func configureDeveloperTerms() {
        guard let window = view.window else { return }
        DeveloperLexiconDialog().present(in: window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .save(let terms):
                DeveloperLexiconStore.save(terms)
                self.detail.stringValue = "开发术语词库已保存"
            case .reset:
                DeveloperLexiconStore.restoreDefaults()
                self.detail.stringValue = "开发术语词库已恢复默认"
            case .cancel:
                break
            }
        }
    }

    @objc func configureScreenshotSaveLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择截图保存位置"
        panel.message = "截图会直接保存到这个文件夹；如果位置不可用，会自动回到下载文件夹。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ScreenshotSaveLocationStore.directory

        guard panel.runModal() == .OK, let url = panel.url else {
            refreshScreenshotSaveLocationButton()
            return
        }
        ScreenshotSaveLocationStore.save(url)
        refreshScreenshotSaveLocationButton()
        detail.stringValue = "截图保存位置已更新：\(ScreenshotSaveLocationStore.displayName)"
    }

    @objc func configureBacklogDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择需求池"
        panel.message = "说出“存入需求池”“保存需求”等语音后，TypeWhale 会把整理后的需求 Markdown 保存到这个文件夹。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = BacklogDirectoryStore.directory

        guard panel.runModal() == .OK, let url = panel.url else {
            refreshBacklogDirectoryButton()
            return
        }
        BacklogDirectoryStore.save(url)
        refreshBacklogDirectoryButton()
        detail.stringValue = "需求池已更新：\(BacklogDirectoryStore.displayName)"
    }

    @objc func configureDeepSeekAPIKey() {
        guard let window = view.window else { return }
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = DeepSeekAPIKeyStore.hasAPIKey() ? "已保存 Key，输入新 Key 可覆盖" : "sk-..."

        FormSheetController().present(
            in: window,
            title: "DeepSeek API Key",
            message: "用于智能整理和自动翻译，保存到 macOS Keychain。\(AppBrand.displayName) 使用 deepseek-v4-flash，并关闭 thinking。",
            contentView: input,
            contentSize: NSSize(width: 320, height: 24),
            buttons: [
                .init(title: "保存", isDefault: true),
                .init(title: "清除"),
                .init(title: "取消", isCancel: true),
            ]
        ) { [weak self] index in
            guard let self else { return }
            switch index {
            case 0:
                do {
                    try DeepSeekAPIKeyStore.save(input.stringValue)
                    self.refreshDeepSeekKeyButton()
                    if DeepSeekAPIKeyStore.hasAPIKey() {
                        self.detail.stringValue = "DeepSeek Key 已保存，智能整理已启用"
                        ToastPresenter.shared.show("Key 已保存", style: .success)
                    } else {
                        self.detail.stringValue = "未输入 Key，智能整理会回退原文"
                    }
                } catch {
                    self.showDeepSeekKeyError(error)
                }
            case 1:
                DeepSeekAPIKeyStore.delete()
                self.refreshDeepSeekKeyButton()
                self.detail.stringValue = "DeepSeek Key 已清除，智能整理会回退原文"
            default:
                self.refreshDeepSeekKeyButton()
            }
        }
    }

    func showDeepSeekKeyError(_ error: Error) {
        ToastPresenter.shared.show("DeepSeek Key 保存失败，请重试", style: .error, duration: 2.6)
    }

    @objc func showDeepSeekBalance(_ sender: NSButton) {
        if let popover = deepSeekBalancePopover, popover.isShown {
            popover.close()
            return
        }

        let content = DeepSeekBalancePopoverViewController()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 268)
        popover.contentViewController = content
        deepSeekBalancePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)

        content.showLoading()
        Task { [weak self, weak content] in
            guard let self else { return }
            do {
                let balance = try await self.deepSeekBalanceClient.fetch()
                let localSpent = SmartUsageLedgerStore.totalEstimatedCostCNY
                await MainActor.run {
                    content?.show(balance: balance, localSpentCNY: localSpent)
                }
            } catch {
                await MainActor.run {
                    content?.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func toggleLaunchAtLogin() {
        do {
            try LoginItemManager.setEnabled(launchAtLogin.state == .on)
            refreshLaunchAtLoginState()
            if LoginItemManager.isPendingApproval {
                detail.stringValue = "请在系统设置的登录项中允许 \(AppBrand.displayName)"
            }
        } catch {
            refreshLaunchAtLoginState()
            detail.stringValue = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLogin.isEnabled = true
        launchAtLogin.state = (LoginItemManager.isEnabled || LoginItemManager.isPendingApproval) ? .on : .off
        launchAtLogin.needsDisplay = true
        launchAtLogin.toolTip = LoginItemManager.isPendingApproval
            ? "已提交开机启动请求，请在系统设置的登录项中允许 \(AppBrand.displayName)"
            : "登录 macOS 后自动启动 \(AppBrand.displayName)"
    }

    @objc func installModel() {
        onInstallModel?()
    }

    func updateModelState(_ state: SenseVoiceModelInstaller.State) {
        refreshDisplayedModelState(installerState: state)
    }

    func updateFunASRRuntimeState(_ state: FunASRRuntimeInstaller.State) {
        funASRRuntimeInstallerState = state
        refreshDisplayedModelState()
    }

    private func scheduleASRBackendChange(_ backend: ASRBackend, previousBackend: ASRBackend) {
        pendingASRBackendChangeWorkItem?.cancel()
        cancelASRBackendSwitchProgress()
        let generation = UUID()
        asrSwitchGeneration = generation
        asrSwitchTarget = backend
        beginASRBackendSwitchProgress(to: backend, generation: generation)
        LaunchDiagnostics.mark("asr_backend_save backend=\(backend.rawValue)")
        LaunchDiagnostics.mark("asr_backend_apply_scheduled backend=\(backend.rawValue) delay_ms=\(Int(scheduledASRBackendChangeDelay * 1000))")
        detail.stringValue = "识别模型将在约 \(Int(round(scheduledASRBackendChangeDelay))) 秒后切换为：\(backend.displayName)"
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.asrSwitchGeneration == generation else { return }
            self.pendingASRBackendChangeWorkItem = nil
            LaunchDiagnostics.mark("asr_backend_apply backend=\(backend.rawValue)")
            self.showASRBackendWarming(backend)
            guard let onASRBackendChange = self.onASRBackendChange else {
                self.failASRBackendSwitch(to: backend, restoring: previousBackend, error: NSError(domain: "com.waykingah.typewhale.asr-switch", code: 2, userInfo: [NSLocalizedDescriptionKey: "识别切换器未连接"]), generation: generation)
                return
            }
            onASRBackendChange(backend) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.asrSwitchGeneration == generation else { return }
                    switch result {
                    case .success:
                        self.completeASRBackendSwitch(to: backend, generation: generation)
                    case .failure(let error):
                        self.failASRBackendSwitch(to: backend, restoring: previousBackend, error: error, generation: generation)
                    }
                }
            }
        }
        pendingASRBackendChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scheduledASRBackendChangeDelay, execute: workItem)
    }

    private func beginASRBackendSwitchProgress(to backend: ASRBackend, generation: UUID) {
        asrSwitchProgressTimer?.invalidate()
        asrSwitchProgress.isIndeterminate = false
        asrSwitchProgress.doubleValue = 0
        asrSwitchProgress.isHidden = false
        asrSwitchProgressLabel.isHidden = false
        modelEntryName.stringValue = backend.displayName
        modelEntryStatus.stringValue = "等待切换"
        modelEntryStatus.textColor = UITheme.waterInkWarning
        modelEntryDot.layer?.backgroundColor = UITheme.waterInkWarning.cgColor
        let startedAt = ProcessInfo.processInfo.systemUptime
        asrSwitchProgressLabel.stringValue = "正在切换到 \(backend.displayName) · 0%"
        asrSwitchProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, self.asrSwitchGeneration == generation else { timer.invalidate(); return }
            let ratio = min(0.75, max(0, (ProcessInfo.processInfo.systemUptime - startedAt) / self.scheduledASRBackendChangeDelay * 0.75))
            self.asrSwitchProgress.doubleValue = ratio
            self.asrSwitchProgressLabel.stringValue = "正在切换到 \(backend.displayName) · \(Int(ratio * 100))%"
        }
    }

    private func showASRBackendWarming(_ backend: ASRBackend) {
        asrSwitchProgressTimer?.invalidate()
        asrSwitchProgressTimer = nil
        asrSwitchProgress.isIndeterminate = true
        asrSwitchProgress.startAnimation(nil)
        asrSwitchProgressLabel.stringValue = "正在预热 \(backend.displayName)…"
        modelEntryStatus.stringValue = "正在预热"
    }

    private func completeASRBackendSwitch(to backend: ASRBackend, generation: UUID) {
        guard asrSwitchGeneration == generation else { return }
        asrSwitchProgress.stopAnimation(nil)
        asrSwitchProgress.isIndeterminate = false
        asrSwitchProgress.doubleValue = 1
        asrSwitchProgressLabel.stringValue = "\(backend.displayName) 已就绪 · 100%"
        activeASRBackend = backend
        asrSwitchTarget = nil
        var settings = AppSettingsStore.loadMainViewSettings()
        settings.asrBackend = backend
        AppSettingsStore.save(settings)
        modelEntryName.stringValue = backend.displayName
        modelEntryStatus.stringValue = "已就绪"
        modelEntryStatus.textColor = UITheme.brandGreen
        modelEntryDot.layer?.backgroundColor = UITheme.brandGreen.cgColor
        detail.stringValue = "识别模型已切换为：\(backend.displayName)；下一次录音生效"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.asrSwitchGeneration == generation, self.asrSwitchTarget == nil else { return }
            self.asrSwitchProgress.isHidden = true
            self.asrSwitchProgressLabel.isHidden = true
        }
    }

    private func failASRBackendSwitch(to backend: ASRBackend, restoring previousBackend: ASRBackend, error: Error, generation: UUID) {
        guard asrSwitchGeneration == generation else { return }
        cancelASRBackendSwitchProgress(clearTarget: false)
        activeASRBackend = previousBackend
        asrSwitchTarget = nil
        asrBackendMode.select(tag: previousBackend.menuTag)
        var settings = AppSettingsStore.loadMainViewSettings()
        settings.asrBackend = previousBackend
        AppSettingsStore.save(settings)
        modelEntryName.stringValue = previousBackend.displayName
        modelEntryStatus.stringValue = "切换失败 · 已恢复"
        modelEntryStatus.textColor = .systemRed
        modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        asrSwitchProgress.isIndeterminate = false
        asrSwitchProgress.doubleValue = 0
        asrSwitchProgress.isHidden = false
        asrSwitchProgressLabel.isHidden = false
        asrSwitchProgressLabel.stringValue = "无法切换到 \(backend.displayName)：\(error.localizedDescription)"
        detail.stringValue = asrSwitchProgressLabel.stringValue
    }

    private func cancelASRBackendSwitchProgress(clearTarget: Bool = true) {
        asrSwitchProgressTimer?.invalidate()
        asrSwitchProgressTimer = nil
        asrSwitchProgress.stopAnimation(nil)
        if clearTarget { asrSwitchTarget = nil }
    }

    func isASRBackendReadyForSelection(_ backend: ASRBackend) -> Bool {
        guard let descriptor = liveASRModelRegistry.descriptor(for: backend.candidateID),
              descriptor.productionReady, descriptor.readiness == .ready else { return false }
        switch descriptor.engine {
        case .sherpa:
            return true
        case .funASR:
            let runtime = AppPaths.runtimes.appendingPathComponent("funasr/\(FunASRRuntimeManifest.version)", isDirectory: true)
            guard case .ready = ManagedFunASRRuntime(rootURL: runtime).structuralState else { return false }
            return true
        case .mlx:
            let runtime = AppPaths.runtimes.appendingPathComponent("mlx-asr/\(MLXASRRuntimeManifest.version)", isDirectory: true)
            if case .ready = ManagedMLXASRRuntime(rootURL: runtime).structuralState { return true }
            return false
        }
    }

    func refreshDisplayedModelState(installerState state: SenseVoiceModelInstaller.State? = nil) {
        let selectedBackend = (asrSwitchTarget ?? activeASRBackend).resolvedBackend
        modelEntryName.stringValue = selectedBackend.displayName
        if selectedBackend != .senseVoice,
           let descriptor = liveASRModelRegistry.descriptor(for: selectedBackend.candidateID),
           descriptor.engine != .funASR {
            let ready = descriptor.readiness == .ready && descriptor.productionReady
            modelEntryStatus.stringValue = ready ? "已就绪" : "不可用"
            modelEntryStatus.textColor = ready ? UITheme.sectionTitle : .systemOrange
            modelEntryDot.layer?.backgroundColor = (ready ? UITheme.sectionTitle : NSColor.systemOrange).cgColor
            modelValue.toolTip = descriptor.modelDirectory.path
            switch descriptor.readiness {
            case .ready:
                modelValue.stringValue = ready ? "已接入最终识别与测速" : "模型已发现，尚未通过真实转写准入"
            case .validating:
                modelValue.stringValue = "模型正在验证"
            case .unavailable(let reason):
                modelValue.stringValue = reason
            }
            modelValue.textColor = ready ? UITheme.sectionTitle : .systemOrange
            modelPathLabel.stringValue = descriptor.modelDirectory.path
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
            return
        }
        if selectedBackend != .senseVoice {
            let root = ManagedASRModelCatalog.rootDirectory(in: AppPaths.models)
            let model = ManagedASRModelCatalog.asrModels.first { $0.id == "fun-asr-nano-2512" }
            let primaryModelReady = model?.isInstalled(in: root) == true
            let modelReady = primaryModelReady
            let destination = model.map { $0.directory(in: root) }
            let runtimeRoot = AppPaths.runtimes.appendingPathComponent(
                "funasr/\(FunASRRuntimeManifest.version)",
                isDirectory: true
            )
            let runtimeReady: Bool
            if case .ready = ManagedFunASRRuntime(rootURL: runtimeRoot).structuralState {
                runtimeReady = true
            } else {
                runtimeReady = false
            }
            modelProgress.isHidden = true
            modelPathLabel.stringValue = destination?.path ?? "—"
            modelValue.toolTip = destination?.path
            if modelReady, case .installing(let message) = funASRRuntimeInstallerState {
                modelEntryStatus.stringValue = "安装中"
                modelEntryStatus.textColor = UITheme.sectionTitle
                modelEntryDot.layer?.backgroundColor = UITheme.sectionTitle.cgColor
                modelValue.stringValue = message
                modelValue.textColor = UITheme.sectionTitle
                modelInstallButton.isHidden = false
                modelInstallButton.isEnabled = false
                modelInstallButton.title = "正在安装…"
            } else if modelReady, case .failed(let message) = funASRRuntimeInstallerState {
                modelEntryStatus.stringValue = "安装失败"
                modelEntryStatus.textColor = .systemRed
                modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
                modelValue.stringValue = message
                modelValue.textColor = .systemRed
                modelInstallButton.isHidden = false
                modelInstallButton.isEnabled = true
                modelInstallButton.title = "重试安装"
            } else if modelReady && runtimeReady {
                modelEntryStatus.stringValue = "已就绪"
                modelEntryStatus.textColor = UITheme.brandGreen
                modelEntryDot.layer?.backgroundColor = UITheme.brandGreen.cgColor
                modelValue.stringValue = "最终识别已就绪 · 实时预览继续使用 SenseVoice"
                modelValue.textColor = UITheme.brandGreen
                modelInstallButton.isHidden = true
            } else if !primaryModelReady {
                modelEntryStatus.stringValue = "模型未安装"
                modelEntryStatus.textColor = .systemOrange
                modelEntryDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                modelValue.stringValue = "请先在模型列表下载 \(selectedBackend.displayName)"
                modelValue.textColor = .systemOrange
                modelInstallButton.isHidden = true
            } else {
                modelEntryStatus.stringValue = "缺少运行环境"
                modelEntryStatus.textColor = .systemOrange
                modelEntryDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                modelValue.stringValue = "模型已下载，需要安装 TypeWhale 管理的 FunASR 运行环境"
                modelValue.textColor = .systemOrange
                modelInstallButton.isHidden = false
                modelInstallButton.isEnabled = true
                modelInstallButton.title = "安装运行环境"
            }
            return
        }

        let state = state ?? (SenseVoiceModelManifest.preferredModelDirectory == nil ? .missing : .ready)
        switch state {
        case .missing:
            modelEntryStatus.stringValue = "未安装"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = nil
            modelValue.stringValue = "SenseVoice int8 缺失，请先安装"
            modelValue.textColor = .systemRed
            modelPathLabel.stringValue = "—"
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "安装模型"
        case .ready:
            let sensePath = SenseVoiceModelManifest.preferredModelDirectory?.path ?? ""
            modelEntryName.stringValue = "SenseVoice int8"
            modelEntryStatus.stringValue = "已就绪"
            modelEntryStatus.textColor = UITheme.brandGreen
            modelEntryDot.layer?.backgroundColor = UITheme.brandGreen.cgColor
            modelValue.toolTip = sensePath
            modelValue.stringValue = "本地模型已就绪，可离线识别"
            modelValue.textColor = UITheme.brandGreen
            modelPathLabel.stringValue = sensePath.isEmpty ? "内置模型" : sensePath
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
        case .downloading(let progress):
            modelEntryStatus.stringValue = "安装中 \(Int(progress * 100))%"
            modelEntryStatus.textColor = .secondaryLabelColor
            modelEntryDot.layer?.backgroundColor = UITheme.waterInkWarning.cgColor
            modelValue.toolTip = nil
            modelValue.stringValue = "正在安装 SenseVoice · \(Int(progress * 100))%"
            modelValue.textColor = UITheme.waterInkMuted
            modelProgress.doubleValue = progress
            modelProgress.isHidden = false
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = false
            modelInstallButton.title = "安装中"
        case .failed(let message):
            modelEntryStatus.stringValue = "安装失败"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = message
            modelValue.stringValue = message
            modelValue.textColor = .systemRed
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "重试安装"
        }
    }

    func updateInputBands(_ bands: [Float]) {
        waveform.update(bands)
    }

    func resetInputBands() {
        waveform.reset()
    }

    func setPrimaryStatus(
        _ text: String,
        detail detailText: String? = nil,
        tone: PrimaryStatusTone,
        resetWaveform: Bool = false
    ) {
        status.stringValue = text
        if let detailText {
            detail.stringValue = detailText
        }
        statusDot.layer?.backgroundColor = statusColor(for: tone).cgColor
        if tone == .processing {
            processingProgress.isHidden = false
            processingProgress.startAnimation(nil)
        } else {
            processingProgress.stopAnimation(nil)
            processingProgress.isHidden = true
        }
        if resetWaveform {
            resetInputBands()
        }
    }

    func statusColor(for tone: PrimaryStatusTone) -> NSColor {
        switch tone {
        case .idle, .success:
            return UITheme.brandGreen
        case .listening:
            return UITheme.brandGreen
        case .processing:
            return UITheme.waterInkWarning
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    @objc func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openScreenRecording() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func openKeyboard() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    var realtimePreviewEnabled: Bool {
        realtime.state == .on
    }

    var shadowPreviewEnabled: Bool {
        shadowPreviewExperiment.state == .on
    }

    @objc func saveShadowPreviewSettings() {
        let enabled = shadowPreviewExperiment.state == .on
        ShadowPreviewSettingsStore().save(ShadowPreviewSettings(isEnabled: enabled))
        NotificationCenter.default.post(
            name: .shadowPreviewSettingDidChange,
            object: enabled
        )
    }

    @objc func saveOnlineASRSettings() {
        let rawValue = onlineASRProviderMode.selectedItem?.representedObject as? String
        let selection = rawValue.flatMap(OnlineASRProviderSelection.init(rawValue:)) ?? .off
        OnlineASRSettingsStore().save(OnlineASRSettings(selection: selection))
        NotificationCenter.default.post(name: .shadowPreviewSettingDidChange, object: selection)
        let credentialStore = OnlineASRCredentialStore()
        let credentialConfigured: Bool
        switch selection {
        case .off: credentialConfigured = true
        case .doubao: credentialConfigured = credentialStore.has(.doubaoAPIKey)
        case .mimoV25: credentialConfigured = credentialStore.has(.mimoAPIKey)
        }
        if selection == .off {
            detail.stringValue = "在线旁路已关闭；下一轮录音继续使用本地旁路。"
        } else if !credentialConfigured {
            detail.stringValue = "\(selection.displayName) 未配置 Key；不会发送在线音频，下一轮继续使用本地旁路。"
            ToastPresenter.shared.show("\(selection.displayName) 未配置 Key", style: .info, duration: 2.6)
        } else {
            detail.stringValue = "已选择\(selection.displayName)；将在下一轮录音开始时生效。"
        }
    }

    @objc func configureDoubaoASRKey() {
        presentOnlineASRKeySheet(kind: .doubaoAPIKey, providerName: "豆包 ASR")
    }

    @objc func configureMiMoASRKey() {
        presentOnlineASRKeySheet(kind: .mimoAPIKey, providerName: "MiMo‑V2.5-ASR")
    }

    private func presentOnlineASRKeySheet(
        kind: OnlineASRCredentialKind,
        providerName: String
    ) {
        guard let window = view.window else { return }
        let credentialStore = OnlineASRCredentialStore()
        let visibleLabel = NSTextField(labelWithString: "API Key")
        visibleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        visibleLabel.textColor = .labelColor
        let input = NSSecureTextField(frame: .zero)
        input.placeholderString = credentialStore.has(kind)
            ? "已保存；输入新 Key 可覆盖"
            : "粘贴 API Key"
        input.setAccessibilityLabel("\(providerName) API Key 安全输入")
        let content = NSStackView(views: [visibleLabel, input])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        input.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        FormSheetController().present(
            in: window,
            title: "\(providerName) Key",
            message: "只保存到 macOS Keychain。Key 内容不会再次显示；在线音频仅在选择该服务并开始下一轮录音后发送。",
            contentView: content,
            contentSize: NSSize(width: 340, height: 48),
            buttons: [
                .init(title: "保存", isDefault: true),
                .init(title: "清除"),
                .init(title: "取消", isCancel: true),
            ]
        ) { [weak self] index in
            guard let self else { return }
            switch index {
            case 0:
                do {
                    try OnlineASRCredentialStore().save(input.stringValue, for: kind)
                    self.refreshOnlineASRCredentialButtons()
                    let configured = OnlineASRCredentialStore().has(kind)
                    self.detail.stringValue = configured
                        ? "\(providerName) Key 已保存；下一轮选择该服务时生效。"
                        : "未输入 Key；\(providerName) 在线旁路不会启动。"
                    ToastPresenter.shared.show(configured ? "Key 已保存" : "未保存空 Key", style: configured ? .success : .info)
                } catch {
                    ToastPresenter.shared.show("Key 保存失败，请重试", style: .error, duration: 2.6)
                }
            case 1:
                OnlineASRCredentialStore().delete(kind)
                self.refreshOnlineASRCredentialButtons()
                self.detail.stringValue = "\(providerName) Key 已清除；在线旁路不会启动。"
            default:
                self.refreshOnlineASRCredentialButtons()
            }
        }
    }

    @objc func saveExperimentalPreviewSettings() {
        if longFormIncrementalOutputExperiment.state == .on {
            correctedPreviewExperiment.state = .on
        }
        normalizeExperimentalPreviewSettings(persist: true, restoreSavedPreference: false)
        saveSettings()
    }

    func normalizeExperimentalPreviewSettings(persist: Bool, restoreSavedPreference: Bool) {
        let supportsSenseVoice = true
        let store = ExperimentalPreviewSettingsStore()
        let requested = restoreSavedPreference
            ? store.load()
            : ExperimentalPreviewSettings(
                correctedPreviewEnabled: correctedPreviewExperiment.state == .on,
                longFormIncrementalOutputEnabled: longFormIncrementalOutputExperiment.state == .on
            )
        let normalized = requested.normalized(supportsSenseVoice: supportsSenseVoice)
        correctedPreviewExperiment.state = normalized.correctedPreviewEnabled ? .on : .off
        longFormIncrementalOutputExperiment.state = normalized.longFormIncrementalOutputEnabled ? .on : .off
        correctedPreviewExperiment.isEnabled = supportsSenseVoice
            && longFormIncrementalOutputExperiment.state == .off
        longFormIncrementalOutputExperiment.isEnabled = supportsSenseVoice
        if persist && !restoreSavedPreference {
            store.save(requested.normalized(supportsSenseVoice: true))
        }
    }

    var experimentalPreviewSettings: ExperimentalPreviewSettings {
        ExperimentalPreviewSettings(
            correctedPreviewEnabled: correctedPreviewExperiment.state == .on,
            longFormIncrementalOutputEnabled: false
        ).normalized(supportsSenseVoice: true)
    }

    var previewTheme: PreviewTheme {
        selectedPreviewTheme
    }

    var autoFinishAfterPauseEnabled: Bool {
        autoFinish.state == .on
    }

    var duckSystemAudioWhileRecordingEnabled: Bool {
        duckSystemAudio.state == .on
    }

    var pauseSystemMediaWhileRecordingEnabled: Bool {
        pauseSystemMedia.state == .on
    }

    var reRecognizeWholeRecordingAfterStopEnabled: Bool {
        reRecognizeWholeRecordingAfterStop.state == .on
    }

    var selectedAudioInputDeviceUID: String {
        guard let representedObject = audioInputDeviceMode.selectedItem?.representedObject as? String else {
            return AudioInputDevice.systemDefaultUID
        }
        return representedObject
    }

    var preferBuiltInMicForBluetoothAudioEnabled: Bool {
        preferBuiltInMicForBluetoothAudio.state == .on
    }

    var asrBackend: ASRBackend {
        ASRBackend.fromMenuTag(asrBackendMode.selectedTag)
    }

    var smartRewritePreference: SmartRewritePreference {
        SmartRewritePreference.fromMenuTag(smartRewriteMode.selectedItem?.tag ?? 0)
    }

    var smartAIModel: SmartAIModel {
        let primary = SmartAIModel.fromMenuTag(smartAIModelMode.selectedItem?.tag ?? 0)
        let duplicate = SmartAIModel.fromMenuTag(modelTabSmartAIModelMode.selectedItem?.tag ?? 0)
        guard primary != duplicate else { return primary }
        let stored = SmartAIModelStore.load()
        if duplicate != stored { return duplicate }
        return primary
    }

    var screenshotArchivePreference: SmartRewritePreference {
        SmartRewritePreference.fromMenuTag(
            screenshotArchiveMode.selectedItem?.tag ?? ScreenshotArchiveModeStore.defaultMode.menuTag
        )
    }

    var ideaPillRewritePreference: SmartRewritePreference {
        guard let rawValue = ideaPillRewriteMode.selectedItem?.representedObject as? String,
              let preference = SmartRewritePreference(rawValue: rawValue) else {
            return IdeaPillRewriteModeStore.defaultMode
        }
        return preference
    }

    /// 循环切换到下一个整理模式，持久化并返回新模式（供胶囊手动切换调用）。
    @discardableResult
    func cycleSmartRewritePreference() -> SmartRewritePreference {
        let all = SmartRewritePreference.allCases
        let index = all.firstIndex(of: smartRewritePreference) ?? 0
        let next = all[(index + 1) % all.count]
        smartRewriteMode.selectItem(withTag: next.menuTag)
        saveSettings()
        return next
    }

    var autoTranslateEnabled: Bool {
        autoTranslate.state == .on
    }

    var translationDirection: SmartTranslationDirection {
        SmartTranslationDirection.fromMenuTag(translationDirectionMode.selectedItem?.tag ?? 0)
    }

    var openClawSettings: OpenClawSettings {
        OpenClawSettings(
            gatewayURL: openClawGatewayField.stringValue,
            agentID: openClawAgentField.stringValue,
            sessionKey: openClawSessionField.stringValue,
            cliPath: openClawCLIPathField.stringValue
        )
    }

    var openClawVoiceSettings: OpenClawVoiceSettings {
        OpenClawVoiceSettings(
            enabled: openClawVoiceEnabledSwitch.state == .on,
            volume: openClawVoiceVolumeSlider.doubleValue,
            speechRate: openClawVoiceRateSlider.doubleValue,
            engine: .zipVoice,
            voiceID: openClawVoiceMode.selectedItem?.representedObject as? String
                ?? OpenClawVoiceSettings.default.voiceID,
            playbackPolicy: selectedVoiceMenuValue(openClawVoicePlaybackMode, fallback: OpenClawVoiceSettings.default.playbackPolicy),
            interruptPolicy: selectedVoiceMenuValue(openClawVoiceInterruptMode, fallback: OpenClawVoiceSettings.default.interruptPolicy)
        )
    }

    private func selectedVoiceMenuValue<Value: RawRepresentable>(
        _ popup: NSPopUpButton,
        fallback: Value
    ) -> Value where Value.RawValue == String {
        guard let rawValue = popup.selectedItem?.representedObject as? String,
              let value = Value(rawValue: rawValue) else {
            return fallback
        }
        return value
    }

    // MARK: - 调试：晨雾浅色 / 深色主题切换（方案 C 逐步落地）
    // 切换开关后自动重启，让 loadView 以新主题从头装配，避免半初始化视图的重建问题。
    @objc func toggleMistThemeDebug(_ sender: Any?) {
        AppSettingsStore.useMistLightTheme.toggle()
        relaunchApp()
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
