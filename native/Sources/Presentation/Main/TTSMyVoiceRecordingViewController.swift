import AppKit
import AVFAudio

final class TTSMyVoiceRecordingViewController: NSViewController {
    enum State: Equatable {
        case idle
        case countdown
        case recording
        case validating
        case ready
        case previewing
        case saving
        case failed(String)
    }

    typealias ClonePreview = (
        TTSLabPersonalVoiceCandidate,
        @escaping (Result<URL, Error>) -> Void
    ) -> Void

    private let store: TTSLabPersonalVoiceStore
    private let clonePreview: ClonePreview
    private let onSaved: (TTSLabVoice) -> Void
    private lazy var recorder = AudioRecorder(outputURLProvider: { [captureRoot] in
        captureRoot.appendingPathComponent("latest.wav")
    })
    private let captureRoot: URL
    private let promptLabel = NSTextField(wrappingLabelWithString: TTSLabPersonalVoiceStore.referenceText)
    private let guidanceLabel = NSTextField(wrappingLabelWithString: "请用自然、稳定的语速读出下面的句子。")
    private let privacyLabel = NSTextField(wrappingLabelWithString: "录音和克隆参考仅保存在这台 Mac，不会上传。")
    private let statusLabel = NSTextField(wrappingLabelWithString: "准备好后开始录音")
    private let timeLabel = NSTextField(labelWithString: "0.0 / 3.0 秒")
    private let levelIndicator = NSProgressIndicator()
    private let primaryButton = NSButton(title: "开始录音", target: nil, action: nil)
    private let originalButton = NSButton(title: "试听原音", target: nil, action: nil)
    private let cloneButton = NSButton(title: "试听克隆", target: nil, action: nil)
    private let rerecordButton = NSButton(title: "重新录制", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存为“我的声音”", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let player = TTSLabAudioPlayer()
    private var state: State = .idle
    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var candidate: TTSLabPersonalVoiceCandidate?
    private var clonePreviewURL: URL?
    private var clonePreviewSucceeded = false

    init(
        store: TTSLabPersonalVoiceStore,
        clonePreview: @escaping ClonePreview,
        onSaved: @escaping (TTSLabVoice) -> Void
    ) {
        self.store = store
        self.clonePreview = clonePreview
        self.onSaved = onSaved
        captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TypeWhale-PersonalVoice-\(UUID().uuidString)",
            isDirectory: true
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "录制我的声音")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        promptLabel.font = .systemFont(ofSize: 24, weight: .medium)
        promptLabel.alignment = .center
        promptLabel.textColor = UITheme.waterInkText
        promptLabel.wantsLayer = true
        promptLabel.layer?.backgroundColor = UITheme.waterInkBackground.withAlphaComponent(0.5).cgColor
        promptLabel.layer?.cornerRadius = 12
        promptLabel.setAccessibilityLabel("固定录音文字")
        guidanceLabel.alignment = .center
        guidanceLabel.textColor = UITheme.waterInkMuted
        privacyLabel.font = .systemFont(ofSize: 11)
        privacyLabel.textColor = UITheme.waterInkMuted
        privacyLabel.alignment = .center
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.alignment = .center

        levelIndicator.style = .bar
        levelIndicator.minValue = 0
        levelIndicator.maxValue = 1
        levelIndicator.doubleValue = 0
        levelIndicator.isIndeterminate = false
        levelIndicator.setAccessibilityLabel("麦克风输入音量")

        [primaryButton, originalButton, cloneButton, rerecordButton, saveButton, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed)
        originalButton.target = self
        originalButton.action = #selector(playOriginal)
        cloneButton.target = self
        cloneButton.action = #selector(playClone)
        rerecordButton.target = self
        rerecordButton.action = #selector(resetRecording)
        saveButton.target = self
        saveButton.action = #selector(save)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        primaryButton.setAccessibilityLabel("开始或停止录制我的声音")
        originalButton.setAccessibilityLabel("试听我的原始录音")
        cloneButton.setAccessibilityLabel("生成并试听克隆声音")
        saveButton.setAccessibilityLabel("保存我的声音参考")

        let previewRow = NSStackView(views: [originalButton, cloneButton, rerecordButton])
        previewRow.orientation = .horizontal
        previewRow.spacing = 8
        previewRow.alignment = .centerY
        let bottomRow = NSStackView(views: [cancelButton, NSView(), saveButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY

        let stack = NSStackView(views: [
            title, guidanceLabel, promptLabel, timeLabel, levelIndicator,
            statusLabel, primaryButton, previewRow, privacyLabel, bottomRow,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX
        root.addSubview(stack)
        [promptLabel, guidanceLabel, statusLabel, privacyLabel, bottomRow].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            promptLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
            levelIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.72),
            root.widthAnchor.constraint(equalToConstant: 560),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 410),
        ])
        view = root
        recorder.onInputLevelDb = { [weak self] db in
            self?.levelIndicator.doubleValue = max(0, min(1, (Double(db) + 60) / 60))
        }
        apply(.idle)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        cleanup()
    }

    @objc private func primaryPressed() {
        switch state {
        case .idle, .failed:
            requestPermissionAndCountdown()
        case .recording:
            guard elapsed >= 1.0 else { return }
            finishRecording()
        default:
            break
        }
    }

    private func requestPermissionAndCountdown() {
        switch PermissionDiagnosticsProvider.microphoneAccessState() {
        case .authorized:
            beginCountdown()
        case .notDetermined:
            PermissionDiagnosticsProvider.requestMicrophone { [weak self] granted in
                granted ? self?.beginCountdown() : self?.apply(.failed("未获得麦克风权限，请在系统设置中允许 TypeWhale Pro 使用麦克风"))
            }
        case .denied:
            apply(.failed("麦克风权限已关闭，请在“系统设置 → 隐私与安全性 → 麦克风”中开启"))
        }
    }

    private func beginCountdown() {
        clearCandidate()
        apply(.countdown)
        var remaining = 0.8
        statusLabel.stringValue = "即将开始 · \(String(format: "%.1f", remaining))"
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] timer in
            guard let self else { timer.invalidate(); return }
            remaining -= 0.1
            if remaining <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.beginRecording()
            } else {
                self.statusLabel.stringValue = "即将开始 · \(String(format: "%.1f", remaining))"
            }
        }
    }

    private func beginRecording() {
        do {
            try FileManager.default.createDirectory(at: captureRoot, withIntermediateDirectories: true)
            try recorder.start(
                taskID: UUID(),
                realtimeEnabled: false,
                inputDeviceID: nil,
                inputDeviceName: "跟随系统"
            )
            recordingStartedAt = Date()
            apply(.recording)
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
                [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.timeLabel.stringValue = String(format: "%.1f / 3.0 秒", self.elapsed)
                self.primaryButton.isEnabled = self.elapsed >= 1.0
                // AudioRecorder intentionally retains about 0.25 s of tail context.
                // Stop capture before the reference pack's strict 3 s ceiling so a
                // normal automatic recording cannot reject itself as overlong.
                if self.elapsed >= 2.70 { self.finishRecording() }
            }
        } catch {
            apply(.failed(error.localizedDescription))
        }
    }

    private var elapsed: TimeInterval {
        recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    private func finishRecording() {
        guard state == .recording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        apply(.validating)
        do {
            guard let (url, _) = try recorder.stop() else {
                throw TTSLabPersonalVoiceValidationError.tooQuiet
            }
            let next = try store.prepareCandidate(from: url)
            try? FileManager.default.removeItem(at: url)
            candidate = next
            apply(.ready)
        } catch {
            recorder.cancel()
            apply(.failed(error.localizedDescription))
        }
    }

    @objc private func playOriginal() {
        guard let candidate else { return }
        apply(.previewing)
        player.play(candidate.referenceURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.apply(.ready)
                case .failure(let error): self?.apply(.failed(error.localizedDescription))
                }
            }
        }
    }

    @objc private func playClone() {
        guard let candidate else { return }
        apply(.previewing)
        statusLabel.stringValue = "正在生成克隆试听…"
        clonePreview(candidate) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.clonePreviewSucceeded = true
                    self.clonePreviewURL = url
                    self.statusLabel.stringValue = "正在播放克隆试听"
                    self.player.play(url) { [weak self] playback in
                        DispatchQueue.main.async {
                            switch playback {
                            case .success: self?.apply(.ready)
                            case .failure(let error): self?.apply(.failed(error.localizedDescription))
                            }
                        }
                    }
                case .failure(let error):
                    self.apply(.failed("克隆试听失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    @objc private func resetRecording() {
        player.stop()
        clearCandidate()
        apply(.idle)
    }

    @objc private func save() {
        guard clonePreviewSucceeded, let candidate else { return }
        apply(.saving)
        do {
            try store.install(candidate)
            self.candidate = nil
            guard let voice = store.discoverVoice() else {
                throw TTSLabPersonalVoiceValidationError.damaged("保存后校验失败")
            }
            onSaved(voice)
            dismissSheet()
        } catch {
            apply(.failed(error.localizedDescription))
        }
    }

    @objc private func cancel() {
        dismissSheet()
    }

    private func dismissSheet() {
        guard let window = view.window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            dismiss(nil)
        }
    }

    private func apply(_ next: State) {
        state = next
        let ready = next == .ready
        primaryButton.isHidden = ready || next == .previewing || next == .saving
        previewControls(ready)
        saveButton.isEnabled = ready && clonePreviewSucceeded
        cancelButton.isEnabled = next != .saving
        switch next {
        case .idle:
            primaryButton.title = "开始录音"
            primaryButton.isEnabled = true
            statusLabel.stringValue = "准备好后开始录音"
            timeLabel.stringValue = "0.0 / 3.0 秒"
            levelIndicator.doubleValue = 0
        case .countdown:
            primaryButton.isEnabled = false
        case .recording:
            primaryButton.title = "停止录音"
            primaryButton.isEnabled = false
            statusLabel.stringValue = "正在录音，请读出引导句"
        case .validating:
            statusLabel.stringValue = "正在检查录音质量…"
        case .ready:
            statusLabel.stringValue = clonePreviewSucceeded
                ? "试听通过，可以保存"
                : "录音合格，请试听克隆效果后保存"
        case .previewing:
            statusLabel.stringValue = "正在试听…"
        case .saving:
            statusLabel.stringValue = "正在安全保存个人音色…"
        case .failed(let message):
            primaryButton.title = "重新录音"
            primaryButton.isEnabled = true
            statusLabel.stringValue = message
        }
    }

    private func previewControls(_ enabled: Bool) {
        originalButton.isHidden = !enabled
        cloneButton.isHidden = !enabled
        rerecordButton.isHidden = !enabled
        originalButton.isEnabled = enabled
        cloneButton.isEnabled = enabled
        rerecordButton.isEnabled = enabled
    }

    private func clearCandidate() {
        if let candidate { store.discard(candidate) }
        candidate = nil
        clonePreviewSucceeded = false
        if let clonePreviewURL { try? FileManager.default.removeItem(at: clonePreviewURL) }
        clonePreviewURL = nil
    }

    private func cleanup() {
        countdownTimer?.invalidate()
        recordingTimer?.invalidate()
        recorder.cancel()
        player.stop()
        clearCandidate()
        try? FileManager.default.removeItem(at: captureRoot)
    }
}
