import AppKit

extension MainViewController {
    func buildTTSReadingLabContent() -> NSView {
        if !ttsReadingLabConfigured {
            configureTTSReadingLab()
        }
        return ttsReadingLabView
    }

    func configureTTSReadingLab() {
        ttsReadingLabConfigured = true
        ttsReadingLabView.textView.string = ttsReadingLabSettings.loadText()
        do {
            let resourcesURL = Bundle.main.resourceURL!
            let runtimeRoot = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(
                "TypeWhale Pro/Runtimes/tts",
                isDirectory: true
            )
            let availability = TTSLabRuntimeAvailability(
                resolver: TTSLabRuntimeResolver(
                    resourcesURL: resourcesURL,
                    managedRuntimeRoot: runtimeRoot
                ),
                resourcesURL: resourcesURL
            )
            let qualificationStore = TTSLabVoiceQualificationStore()
            ttsReadingLabModels = try TTSLabModelCatalog.installedModels().map { model in
                let model = model.withRuntimeReadiness(availability.readiness(for: model))
                guard let fingerprint = TTSLabVoiceCatalog.fingerprint(for: model.id) else {
                    return model
                }
                let qualified = qualificationStore.qualifiedVoiceIDs(
                    modelID: model.id,
                    fingerprint: fingerprint
                )
                let voices = TTSLabVoiceCatalog.availableVoices(
                    qualifiedVoiceIDs: qualified,
                    personalVoice: ttsPersonalVoiceStore.discoverVoice()
                )
                return model.withVoices(voices)
            }
        } catch {
            ttsReadingLabModels = []
            ttsReadingLabView.statusLabel.stringValue = "无法读取本地模型，请重新打开此页面"
        }
        ttsReadingLabView.modelPopup.removeAllItems()
        for model in ttsReadingLabModels {
            ttsReadingLabView.modelPopup.addItem(
                withTitle: "第\(model.tier)梯队 · \(model.displayName) · \(ttsLabStatusText(for: model))"
            )
        }
        if let firstReadyIndex = ttsReadingLabModels.firstIndex(
            where: { $0.runtimeReadiness == .ready }
        ) {
            ttsReadingLabView.modelPopup.selectItem(at: firstReadyIndex)
        }
        if ttsReadingLabModels.isEmpty {
            ttsReadingLabView.modelPopup.addItem(withTitle: "未发现本地朗读模型")
            ttsReadingLabView.modelPopup.isEnabled = false
            ttsReadingLabView.statusLabel.stringValue = "请先准备本地模型"
        } else {
            ttsReadingLabView.modelPopup.isEnabled = true
            let ready = ttsReadingLabModels.filter { $0.runtimeReadiness == .ready }.count
            ttsReadingLabView.statusLabel.stringValue =
                "\(ttsReadingLabModels.count) 个候选模型 · \(ready) 个可测试"
        }
        ttsReadingLabView.onTextChange = { [weak self] text in
            self?.ttsReadingLabSettings.saveText(text)
            self?.refreshTTSReadingLabActions()
        }
        ttsReadingLabView.onModelChange = { [weak self] _ in
            self?.refreshTTSReadingLabVoiceMenu()
            self?.refreshTTSReadingLabActions()
        }
        ttsReadingLabView.onVoiceChange = { [weak self] voiceID in
            guard let self,
                  let model = self.selectedTTSReadingLabModel(),
                  let voiceID else { return }
            self.ttsReadingLabSettings.saveVoiceID(voiceID, modelID: model.id)
            self.refreshTTSReadingLabActions()
        }
        ttsReadingLabView.onPlay = { [weak self] in
            self?.toggleTTSReadingLabPlayback()
        }
        ttsReadingLabView.onReplay = { [weak self] in
            self?.ttsReadingLabService.replayLastOutput()
        }
        ttsReadingLabView.onRecordMyVoice = { [weak self] in
            self?.presentMyVoiceRecordingSheet()
        }
        ttsReadingLabService.onStateChange = { [weak self] state in
            self?.applyTTSReadingLabState(state)
        }
        refreshTTSReadingLabVoiceMenu()
        refreshTTSReadingLabActions()
    }

    func refreshTTSReadingLabActions() {
        let hasText = !ttsReadingLabView.textView.string
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModel = ttsReadingLabModels.indices.contains(
            ttsReadingLabView.modelPopup.indexOfSelectedItem
        )
        let modelReady = hasModel
            && ttsReadingLabModels[ttsReadingLabView.modelPopup.indexOfSelectedItem]
                .runtimeReadiness == .ready
        let selectedModel = selectedTTSReadingLabModel()
        let supportsPresetVoices = selectedModel.map {
            !TTSLabVoiceCatalog.candidates(for: $0.id).isEmpty
        } ?? false
        let voiceReady = !supportsPresetVoices || selectedTTSReadingLabVoice() != nil
        ttsReadingLabView.playButton.isEnabled =
            ttsReadingLabIsRunning || (hasText && modelReady && voiceReady)
        ttsReadingLabView.replayButton.isEnabled =
            !ttsReadingLabIsRunning && ttsReadingLabService.lastOutputURL != nil
        ttsReadingLabView.recordMyVoiceButton.isEnabled = !ttsReadingLabIsRunning
        ttsReadingLabView.modelPopup.isEnabled = !ttsReadingLabIsRunning && hasModel
        ttsReadingLabView.voicePopup.isEnabled =
            !ttsReadingLabIsRunning && (selectedModel?.voices.isEmpty == false)
    }

    func presentMyVoiceRecordingSheet() {
        guard let parentWindow = view.window,
              let model = ttsReadingLabModels.first(where: {
                  $0.id == TTSLabVoiceCatalog.retainedModelID
                      && $0.runtimeReadiness == .ready
              }) else {
            ttsReadingLabView.statusLabel.stringValue = "ZipVoice 尚未准备好，无法录制个人音色"
            return
        }
        let controller = TTSMyVoiceRecordingViewController(
            store: ttsPersonalVoiceStore,
            clonePreview: { [weak self] candidate, completion in
                self?.ttsReadingLabService.generatePersonalVoicePreview(
                    text: "你好，这是我的声音试听。",
                    model: model,
                    candidate: candidate,
                    completion: completion
                )
            },
            onSaved: { [weak self] voice in
                guard let self else { return }
                self.installPersonalVoiceInReadingLab(voice)
                self.ttsMyVoiceRecordingController = nil
            }
        )
        let sheet = NSWindow(contentViewController: controller)
        sheet.title = "录制我的声音"
        sheet.styleMask = [.titled]
        ttsMyVoiceRecordingController = controller
        parentWindow.beginSheet(sheet) { [weak self] _ in
            self?.ttsMyVoiceRecordingController = nil
        }
    }

    private func installPersonalVoiceInReadingLab(_ voice: TTSLabVoice) {
        guard let index = ttsReadingLabModels.firstIndex(where: {
            $0.id == TTSLabVoiceCatalog.retainedModelID
        }) else { return }
        var voices = ttsReadingLabModels[index].voices.filter {
            $0.id != TTSLabPersonalVoiceStore.voiceID
        }
        voices.append(voice)
        ttsReadingLabModels[index] = ttsReadingLabModels[index].withVoices(voices)
        if ttsReadingLabView.modelPopup.indexOfSelectedItem != index {
            ttsReadingLabView.modelPopup.selectItem(at: index)
        }
        refreshTTSReadingLabVoiceMenu()
        if let item = ttsReadingLabView.voicePopup.itemArray.first(where: {
            ($0.representedObject as? String) == voice.id
        }) {
            ttsReadingLabView.voicePopup.select(item)
            ttsReadingLabSettings.saveVoiceID(voice.id, modelID: TTSLabVoiceCatalog.retainedModelID)
        }
        ttsReadingLabView.statusLabel.stringValue = "“我的声音”已保存并选中"
        refreshOpenClawVoiceControls()
        refreshTTSReadingLabActions()
    }

    func toggleTTSReadingLabPlayback() {
        if ttsReadingLabIsRunning {
            ttsReadingLabService.stop()
            return
        }
        let index = ttsReadingLabView.modelPopup.indexOfSelectedItem
        guard ttsReadingLabModels.indices.contains(index) else { return }
        let text = ttsReadingLabView.textView.string
        ttsReadingLabSettings.saveText(text)
        ttsReadingLabActiveText = text
        ttsReadingLabActiveModel = ttsReadingLabModels[index]
        ttsReadingLabActiveVoice = selectedTTSReadingLabVoice()
        ttsReadingLabService.start(
            text: text,
            model: ttsReadingLabModels[index],
            voice: ttsReadingLabActiveVoice
        )
    }

    func refreshTTSReadingLabVoiceMenu() {
        let popup = ttsReadingLabView.voicePopup
        popup.removeAllItems()
        guard let model = selectedTTSReadingLabModel() else {
            popup.addItem(withTitle: "无可用模型")
            popup.isEnabled = false
            return
        }
        let candidates = TTSLabVoiceCatalog.candidates(for: model.id)
        guard !candidates.isEmpty else {
            popup.addItem(withTitle: "固定音色")
            popup.isEnabled = false
            return
        }
        guard !model.voices.isEmpty else {
            popup.addItem(withTitle: "暂无通过测试的音色")
            popup.isEnabled = false
            return
        }
        var previousGroup: TTSLabVoiceGroup?
        for voice in model.voices {
            if voice.group != previousGroup {
                if previousGroup != nil { popup.menu?.addItem(.separator()) }
                let header = NSMenuItem(title: voiceGroupTitle(voice.group), action: nil, keyEquivalent: "")
                header.isEnabled = false
                popup.menu?.addItem(header)
                previousGroup = voice.group
            }
            let item = NSMenuItem(title: voice.menuTitle, action: nil, keyEquivalent: "")
            item.representedObject = voice.id as NSString
            popup.menu?.addItem(item)
        }
        let saved = ttsReadingLabSettings.loadVoiceID(
            modelID: model.id,
            availableVoices: model.voices
        )
        if let saved,
           let item = popup.itemArray.first(where: {
               ($0.representedObject as? String) == saved
           }) {
            popup.select(item)
        } else if let first = popup.itemArray.first(where: { $0.representedObject != nil }) {
            popup.select(first)
        }
        popup.isEnabled = !ttsReadingLabIsRunning
    }

    private func selectedTTSReadingLabModel() -> TTSLabModel? {
        let index = ttsReadingLabView.modelPopup.indexOfSelectedItem
        guard ttsReadingLabModels.indices.contains(index) else { return nil }
        return ttsReadingLabModels[index]
    }

    private func selectedTTSReadingLabVoice() -> TTSLabVoice? {
        guard let model = selectedTTSReadingLabModel(),
              let voiceID = ttsReadingLabView.voicePopup.selectedItem?
                .representedObject as? String else { return nil }
        return model.voices.first(where: { $0.id == voiceID })
    }

    private func voiceGroupTitle(_ group: TTSLabVoiceGroup) -> String {
        switch group {
        case .zipVoice: return "克隆音色（实验）"
        }
    }

    func applyTTSReadingLabState(_ state: TTSReadingLabState) {
        switch state {
        case .idle:
            ttsReadingLabIsRunning = false
            ttsReadingLabView.statusLabel.stringValue = "就绪"
        case .preparing:
            ttsReadingLabIsRunning = true
            ttsReadingLabView.statusLabel.stringValue = "正在冷/热加载模型…"
        case .generating:
            ttsReadingLabIsRunning = true
            ttsReadingLabView.statusLabel.stringValue = "正在生成本地音频…"
        case .playing:
            ttsReadingLabIsRunning = true
            ttsReadingLabView.statusLabel.stringValue = "正在播放"
        case .completed(let metrics, let outputURL, let voiceID):
            ttsReadingLabIsRunning = false
            ttsReadingLabView.statusLabel.stringValue = "播放完成"
            ttsReadingLabView.metricsLabel.stringValue = formatTTSLabMetrics(metrics)
            if let model = ttsReadingLabActiveModel {
                try? ttsReadingLabResultStore.append(
                    model: model,
                    text: ttsReadingLabActiveText,
                    metrics: metrics,
                    outputURL: outputURL,
                    voiceID: voiceID
                )
            }
        case .stopped:
            ttsReadingLabIsRunning = false
            ttsReadingLabView.statusLabel.stringValue = "已停止"
        case .failed(let message):
            ttsReadingLabIsRunning = false
            ttsReadingLabView.statusLabel.stringValue = "失败：\(message)"
        }
        ttsReadingLabView.playButton.title = ttsReadingLabIsRunning ? "停止" : "播放"
        refreshTTSReadingLabActions()
    }

    private func formatTTSLabMetrics(_ metrics: TTSLabMetrics) -> String {
        let memory = ByteCountFormatter.string(
            fromByteCount: metrics.peakRSSBytes,
            countStyle: .memory
        )
        return String(
            format: "%@ · 首音 %.2fs · 生成 %.2fs\n音频 %.2fs · RTF %.2f · 峰值 %@",
            metrics.cold ? "冷启动" : "热启动",
            metrics.firstAudioSeconds,
            metrics.synthesisSeconds,
            metrics.audioSeconds,
            metrics.rtf,
            memory
        )
    }

    private func ttsLabStatusText(
        for model: TTSLabModel,
        isEliminated: Bool = false
    ) -> String {
        if isEliminated { return "已淘汰" }
        switch model.runtimeReadiness {
        case .preparing, .unknown:
            return "运行时准备中"
        case .failed:
            return "测试失败"
        case .unavailable:
            return "权重已下载"
        case .ready:
            switch model.qualification {
            case .passed: return "资格通过"
            case .failed: return "测试失败"
            case .unverified: return "可测试"
            }
        }
    }
}
