import AppKit

extension MainViewController {
    @objc func saveSettings() {
        if autoFinish.state == .on {
            realtime.state = .on
            realtime.needsDisplay = true
        }
        if realtime.state == .off {
            autoFinish.state = .off
            autoFinish.needsDisplay = true
        }
        AppSettingsStore.save(MainViewSettings(
            realtimePreviewEnabled: realtime.state == .on,
            autoFinishAfterPauseEnabled: autoFinish.state == .on,
            duckSystemAudioWhileRecordingEnabled: duckSystemAudio.state == .on,
            micVoiceProcessingEnabled: micNoiseReduction.state == .on,
            asrBackend: asrBackend,
            smartRewritePreference: smartRewritePreference,
            autoTranslateEnabled: autoTranslate.state == .on,
            translationDirection: translationDirection
        ))
        refreshDisplayedModelState()
    }

    @objc func configureSmartRewritePrompts() {
        let dialog = SmartRewritePromptDialog(initialMode: smartRewritePreference.manualMode ?? .developerRequirement)
        switch dialog.runModal() {
        case .save(let mode, let template):
            SmartRewritePromptStore.save(template, for: mode)
            detail.stringValue = "\(mode.displayName)提示词已保存"
        case .reset(let mode):
            SmartRewritePromptStore.reset(mode)
            detail.stringValue = "\(mode.displayName)提示词已恢复默认"
        case .cancel:
            break
        }
    }

    @objc func configureSmartRewriteAutoRules() {
        let dialog = SmartRewriteAutoRuleDialog(configuration: SmartRewriteAutoRuleStore.load())
        switch dialog.runModal() {
        case .save(let configuration):
            SmartRewriteAutoRuleStore.save(configuration)
            detail.stringValue = "智能整理自动范围已保存"
        case .reset:
            SmartRewriteAutoRuleStore.reset()
            detail.stringValue = "智能整理自动范围已恢复默认"
        case .cancel:
            break
        }
    }

    @objc func configureTranslationPrompts() {
        let dialog = SmartTranslationPromptDialog(initialDirection: translationDirection)
        switch dialog.runModal() {
        case .save(let direction, let template):
            SmartTranslationPromptStore.save(template, for: direction)
            detail.stringValue = "\(direction.displayName)提示词已保存"
        case .reset(let direction):
            SmartTranslationPromptStore.reset(direction)
            detail.stringValue = "\(direction.displayName)提示词已恢复默认"
        case .cancel:
            break
        }
    }

    @objc func configureDeveloperTerms() {
        switch DeveloperLexiconDialog().runModal() {
        case .save(let terms):
            DeveloperLexiconStore.save(terms)
            detail.stringValue = "开发术语词库已保存"
        case .reset:
            DeveloperLexiconStore.restoreDefaults()
            detail.stringValue = "开发术语词库已恢复默认"
        case .cancel:
            break
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
        let alert = NSAlert()
        alert.messageText = "DeepSeek API Key"
        alert.informativeText = "用于智能整理和自动翻译，保存到 macOS Keychain。TypeWhale 使用 deepseek-v4-flash，并关闭 thinking。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = DeepSeekAPIKeyStore.hasAPIKey() ? "已保存 Key，输入新 Key 可覆盖" : "sk-..."
        alert.accessoryView = input

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try DeepSeekAPIKeyStore.save(input.stringValue)
                refreshDeepSeekKeyButton()
                detail.stringValue = DeepSeekAPIKeyStore.hasAPIKey()
                    ? "DeepSeek Key 已保存，智能整理已启用"
                    : "未输入 Key，智能整理会回退原文"
            } catch {
                showDeepSeekKeyError(error)
            }
        case .alertSecondButtonReturn:
            DeepSeekAPIKeyStore.delete()
            refreshDeepSeekKeyButton()
            detail.stringValue = "DeepSeek Key 已清除，智能整理会回退原文"
        default:
            refreshDeepSeekKeyButton()
        }
    }

    func showDeepSeekKeyError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "DeepSeek Key 保存失败"
        alert.runModal()
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
                detail.stringValue = "请在系统设置的登录项中允许 TypeWhale"
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
            ? "已提交开机启动请求，请在系统设置的登录项中允许 TypeWhale"
            : "登录 macOS 后自动启动 TypeWhale"
    }

    @objc func installModel() {
        onInstallModel?()
    }

    func updateModelState(_ state: SenseVoiceModelInstaller.State) {
        refreshDisplayedModelState(installerState: state)
    }

    func refreshDisplayedModelState(installerState state: SenseVoiceModelInstaller.State? = nil) {
        let selectedBackend = asrBackend.resolvedBackend
        modelEntryName.stringValue = asrBackend == .automatic
            ? "\(selectedBackend.displayName) · 自动"
            : selectedBackend.displayName
        if selectedBackend == .qwen3ASR {
            if let qwenPath = Qwen3ASRModelManifest.preferredModelDirectory?.path {
                modelEntryStatus.stringValue = "已就绪"
                modelEntryStatus.textColor = .systemGreen
                modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                modelValue.toolTip = qwenPath
                modelValue.stringValue = "Qwen3-ASR 原生模型已就绪，可离线识别"
                modelValue.textColor = .systemGreen
                modelPathLabel.stringValue = qwenPath
                modelProgress.isHidden = true
                modelInstallButton.isHidden = true
                return
            }
            modelEntryStatus.stringValue = "未安装"
            modelEntryStatus.textColor = .systemRed
            modelEntryDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            modelValue.toolTip = Qwen3ASRModelManifest.modelDirectory.path
            modelValue.stringValue = "Qwen3-ASR 模型缺失，自动模式会回退 SenseVoice"
            modelValue.textColor = .systemOrange
            modelPathLabel.stringValue = Qwen3ASRModelManifest.modelDirectory.path
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
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
            modelEntryName.stringValue = asrBackend == .automatic ? "SenseVoice int8 · 自动" : "SenseVoice int8"
            modelEntryStatus.stringValue = "已就绪"
            modelEntryStatus.textColor = .systemGreen
            modelEntryDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            modelValue.toolTip = sensePath
            modelValue.stringValue = "本地模型已就绪，可离线识别"
            modelValue.textColor = .systemGreen
            modelPathLabel.stringValue = sensePath.isEmpty ? "内置模型" : sensePath
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
        case .downloading(let progress):
            modelEntryStatus.stringValue = "安装中 \(Int(progress * 100))%"
            modelEntryStatus.textColor = .secondaryLabelColor
            modelEntryDot.layer?.backgroundColor = UITheme.brandYellow.cgColor
            modelValue.toolTip = nil
            modelValue.stringValue = "正在安装 SenseVoice · \(Int(progress * 100))%"
            modelValue.textColor = .secondaryLabelColor
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
            return .systemGreen
        case .listening:
            return UITheme.brandTeal
        case .processing:
            return UITheme.brandYellow
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

    var autoFinishAfterPauseEnabled: Bool {
        autoFinish.state == .on
    }

    var duckSystemAudioWhileRecordingEnabled: Bool {
        duckSystemAudio.state == .on
    }

    var micVoiceProcessingEnabled: Bool {
        micNoiseReduction.state == .on
    }

    var asrBackend: ASRBackend {
        ASRBackend.fromMenuTag(asrBackendMode.selectedItem?.tag ?? 0)
    }

    var smartRewritePreference: SmartRewritePreference {
        SmartRewritePreference.fromMenuTag(smartRewriteMode.selectedItem?.tag ?? 0)
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
}
