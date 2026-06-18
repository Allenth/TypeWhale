import AppKit
import ApplicationServices

final class MainViewController: NSViewController {
    enum PrimaryStatusTone {
        case idle
        case listening
        case processing
        case success
        case warning
        case error
    }

    private let contentWidth: CGFloat = 660
    private let contentHeight: CGFloat = 858
    private let leftColumnWidth: CGFloat = 212
    private let topInset: CGFloat = 38
    private let recentViewportHeight: CGFloat = 196
    private let brandIconVisibleSize: CGFloat = 64

    let status = label("等待录音", size: 15, weight: .semibold)
    let detail = label("Fn 录音", size: 12)
    let micStatus = label("检测中", size: 12, weight: .medium)
    let accessibilityStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyValue = label(
        HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding).displayName,
        size: 13,
        weight: .semibold
    )
    let secondaryHotkeyValue = label(
        HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)?.displayName ?? "未设置",
        size: 13,
        weight: .medium
    )
    let hotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let hotkeyResetButton = NSButton(title: "恢复 Fn", target: nil, action: nil)
    let secondaryHotkeyCaptureButton = NSButton(title: "录入", target: nil, action: nil)
    let secondaryHotkeyClearButton = NSButton(title: "清空", target: nil, action: nil)
    let modelValue = label("正在检查模型", size: 12, weight: .medium)
    let modelProgress = NSProgressIndicator()
    let modelInstallButton = NSButton(title: "安装模型", target: nil, action: nil)
    let realtime = BrandSwitch()
    let autoFinish = BrandSwitch()
    let duckSystemAudio = BrandSwitch()
    let launchAtLogin = BrandSwitch()
    let realtimeDraft = label("等待实时草稿", size: 12)
    var onInstallModel: (() -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?) -> Void)?

    private let modelEntryName = label("SenseVoice int8", size: 13, weight: .semibold)
    private let modelEntryStatus = label("检查中", size: 11, weight: .medium)
    private let modelEntryDot = NSView()
    private let modelPathLabel = label("", size: 11)
    private let statusDot = NSView()
    private let waveform = MiniWaveformView()

    private let recentStack = FlippedStackView()
    private let recentScroll = NSScrollView()
    private var recentRecords: [RecentTranscription] = []
    private var isCapturingHotkey = false
    private var capturingChannel: SpeechInputChannel?
    private var capturingHotkeySlot: HotkeySlot?
    private var hotkeyCaptureMonitor: Any?
    private var hotkeyCaptureTap: CFMachPort?
    private var hotkeyCaptureSource: CFRunLoopSource?
    private var captureModifierKeyCodes: Set<Int> = []
    private var captureConfirmWorkItem: DispatchWorkItem?
    private var versionHistoryPopover: NSPopover?
    private var modelDetailPopover: NSPopover?
    private lazy var versionHistoryViewController = VersionHistoryViewController()

    private enum HotkeySlot {
        case primary
        case secondary
    }

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        view = root
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: contentWidth),
            view.heightAnchor.constraint(equalToConstant: contentHeight),
        ])

        let darkOverlay = NSView()
        darkOverlay.translatesAutoresizingMaskIntoConstraints = false
        darkOverlay.wantsLayer = true
        darkOverlay.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.36).cgColor
        view.addSubview(darkOverlay)
        NSLayoutConstraint.activate([
            darkOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            darkOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            darkOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            darkOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let settings = AppSettingsStore.loadMainViewSettings()
        realtime.state = settings.realtimePreviewEnabled ? .on : .off
        realtime.target = self; realtime.action = #selector(saveSettings)
        autoFinish.state = settings.autoFinishAfterPauseEnabled ? .on : .off
        autoFinish.target = self; autoFinish.action = #selector(saveSettings)
        duckSystemAudio.state = settings.duckSystemAudioWhileRecordingEnabled ? .on : .off
        duckSystemAudio.target = self; duckSystemAudio.action = #selector(saveSettings)
        refreshLaunchAtLoginState()
        launchAtLogin.target = self; launchAtLogin.action = #selector(toggleLaunchAtLogin)
        configureOptionAccessibility()

        let left = buildLeftColumn()
        let right = buildRightColumn()
        view.addSubview(left)
        view.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.topAnchor.constraint(equalTo: view.topAnchor),
            left.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftColumnWidth),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 22),
            right.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            right.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            right.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])

        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        )
        DispatchQueue.main.async { [weak self] in
            _ = self?.versionHistoryViewController.view
        }
    }

    // MARK: - Left column

    private func buildLeftColumn() -> NSView {
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
        brandIcon.layer?.cornerRadius = 15
        brandIcon.layer?.masksToBounds = true
        let brandTitle = label("TypeWhale", size: 18, weight: .semibold)
        brandTitle.alignment = .center
        let brandVersion = label(versionText(), size: 11, weight: .medium)
        brandVersion.textColor = .secondaryLabelColor
        brandVersion.alignment = .center
        let brandStack = NSStackView(views: [brandIcon, brandTitle, brandVersion])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 6

        let statusPanel = buildStatusPanel()
        let modelEntry = buildModelEntry()

        let historyButton = NSButton(title: " 版本历史", target: self, action: #selector(showVersionHistory(_:)))
        historyButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        historyButton.imagePosition = .imageLeading
        historyButton.bezelStyle = .rounded
        historyButton.controlSize = .regular

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [brandStack, statusPanel, modelEntry, spacer, historyButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: container.topAnchor),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 0.5),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            brandStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelEntry.widthAnchor.constraint(equalTo: stack.widthAnchor),
            historyButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            brandIcon.widthAnchor.constraint(equalToConstant: brandIconVisibleSize),
            brandIcon.heightAnchor.constraint(equalToConstant: brandIconVisibleSize),
        ])
        return container
    }

    private func buildStatusPanel() -> NSView {
        status.alignment = .center
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
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
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        pill.layer?.cornerRadius = 12
        pill.addSubview(pillStack)

        waveform.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView(views: [pill, waveform, detail])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.spacing = 11
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = UITheme.cardFill.cgColor
        box.layer?.cornerRadius = 12
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
            waveform.heightAnchor.constraint(equalToConstant: 34),
            waveform.widthAnchor.constraint(equalTo: inner.widthAnchor),
            box.heightAnchor.constraint(equalToConstant: 128),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            detail.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return box
    }

    private func buildModelEntry() -> NSView {
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

        let box = roundedBox(textStack, hPad: 14, vPad: 12)
        NSLayoutConstraint.activate([
            modelEntryDot.widthAnchor.constraint(equalToConstant: 6),
            modelEntryDot.heightAnchor.constraint(equalToConstant: 6),
            nameRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(showModelDetail(_:)))
        box.addGestureRecognizer(click)
        return box
    }

    // MARK: - Right column

    private func buildRightColumn() -> NSView {
        let micButton = settingsButton("设置", action: #selector(openMicrophone))
        let accessButton = settingsButton("设置", action: #selector(openAccessibility))
        let keyboardButton = settingsButton("设置", action: #selector(openKeyboard))
        let permissionCard = listCard([
            permissionRow(icon: "mic", name: "麦克风", status: micStatus, button: micButton),
            permissionRow(icon: "accessibility", name: "辅助功能", status: accessibilityStatus, button: accessButton),
            permissionRow(icon: "keyboard", name: "全局快捷键", status: hotkeyStatus, button: keyboardButton),
        ])

        [hotkeyValue, secondaryHotkeyValue].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
        }
        hotkeyCaptureButton.target = self
        hotkeyCaptureButton.action = #selector(beginHotkeyCapture)
        hotkeyResetButton.target = self
        hotkeyResetButton.action = #selector(resetHotkey)
        secondaryHotkeyCaptureButton.target = self
        secondaryHotkeyCaptureButton.action = #selector(beginSecondaryHotkeyCapture)
        secondaryHotkeyClearButton.target = self
        secondaryHotkeyClearButton.action = #selector(clearSecondaryHotkey)
        let hotkeyButtons = [hotkeyCaptureButton, hotkeyResetButton, secondaryHotkeyCaptureButton, secondaryHotkeyClearButton]
        hotkeyButtons.forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
            $0.font = .systemFont(ofSize: 12)
        }
        let keycapWidth: CGFloat = 92
        let captureWidth: CGFloat = 54
        let trailingWidth: CGFloat = 74
        let primaryKeycap = KeycapView(hotkeyValue, minWidth: 46, height: 22)
        let secondaryKeycap = KeycapView(secondaryHotkeyValue, minWidth: 46, height: 22)
        [primaryKeycap, secondaryKeycap].forEach {
            $0.widthAnchor.constraint(equalToConstant: keycapWidth).isActive = true
        }
        [hotkeyCaptureButton, secondaryHotkeyCaptureButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: captureWidth).isActive = true
        }
        [hotkeyResetButton, secondaryHotkeyClearButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: trailingWidth).isActive = true
        }
        let primaryName = label("主快捷键", size: 14)
        let primaryRow = NSStackView(views: [primaryName, flexSpacer(), primaryKeycap, hotkeyCaptureButton, hotkeyResetButton])
        let secondaryName = label("备用快捷键", size: 14)
        let secondaryRow = NSStackView(views: [secondaryName, flexSpacer(), secondaryKeycap, secondaryHotkeyCaptureButton, secondaryHotkeyClearButton])
        [primaryRow, secondaryRow].forEach {
            $0.orientation = .horizontal
            $0.alignment = .centerY
            $0.spacing = 8
            $0.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        let hotkeyCard = listCard([primaryRow, secondaryRow])

        let optionCard = listCard([
            optionRow("胶囊实时预览", realtime),
            optionRow("停顿自动完成", autoFinish),
            optionRow("录音时降低电脑声音", duckSystemAudio),
            optionRow("开机自动启动", launchAtLogin),
        ])

        realtimeDraft.textColor = .secondaryLabelColor
        realtimeDraft.maximumNumberOfLines = 2
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
            realtimeDraft.bottomAnchor.constraint(equalTo: draftContent.bottomAnchor),
            draftContent.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
        let draftCard = roundedBox(draftContent, hPad: 15, vPad: 11)

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
        recentScroll.heightAnchor.constraint(equalToConstant: recentViewportHeight).isActive = true
        let recentCard = roundedBox(recentScroll, hPad: 8, vPad: 6)

        let sections = [
            section("权限", permissionCard),
            section("快捷键", hotkeyCard),
            section("选项", optionCard),
            section("实时草稿", draftCard),
            section("最近转录", recentCard),
        ]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for sectionView in sections {
            sectionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        recentStack.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor).isActive = true
        return stack
    }

    private func section(_ title: String, _ card: NSView) -> NSView {
        let stack = NSStackView(views: [sectionHeader(title), card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func settingsButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12)
        button.widthAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    private func permissionRow(icon: String, name: String, status: NSTextField, button: NSButton) -> NSView {
        let iconView = symbolIcon(icon, size: 16)
        let nameLabel = label(name, size: 14)
        status.alignment = .left
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.required, for: .horizontal)
        status.widthAnchor.constraint(equalToConstant: 86).isActive = true
        let row = NSStackView(views: [iconView, nameLabel, flexSpacer(), status, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    private func optionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 14)
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    private func configureOptionAccessibility() {
        realtime.setAccessibilityLabel("胶囊实时预览")
        autoFinish.setAccessibilityLabel("停顿自动完成")
        duckSystemAudio.setAccessibilityLabel("录音时降低电脑声音")
        launchAtLogin.setAccessibilityLabel("开机自动启动")
    }

    private func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.13"
        let build = info?["CFBundleVersion"] as? String ?? "170"
        return "Version \(version) (\(build))"
    }

    private func loadBrandIcon() -> NSImage? {
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

    private func loadAppIcon() -> NSImage? {
        if let image = NSImage(named: "TypeWhale") {
            return image
        }
        if let url = Bundle.main.url(forResource: "TypeWhale", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    @objc private func showVersionHistory(_ sender: NSButton) {
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

    @objc private func showModelDetail(_ sender: NSGestureRecognizer) {
        guard let anchor = sender.view else { return }
        if let popover = modelDetailPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = modelDetailPopover ?? NSPopover()
        if modelDetailPopover == nil {
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 300, height: 240)
            popover.contentViewController = makeModelDetailController()
            modelDetailPopover = popover
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    private func makeModelDetailController() -> NSViewController {
        let icon = symbolIcon("cpu", size: 18, color: UITheme.brandYellow)
        let title = label("SenseVoice int8", size: 14, weight: .semibold)
        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping

        let desc = label("本地离线语音识别模型，全程在本机推理，不上传音频。", size: 12)
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

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
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

    @objc private func saveSettings() {
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
            duckSystemAudioWhileRecordingEnabled: duckSystemAudio.state == .on
        ))
    }

    @objc private func toggleLaunchAtLogin() {
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

    private func refreshLaunchAtLoginState() {
        launchAtLogin.state = (LoginItemManager.isEnabled || LoginItemManager.isPendingApproval) ? .on : .off
        launchAtLogin.needsDisplay = true
        launchAtLogin.toolTip = LoginItemManager.isPendingApproval
            ? "已提交开机启动请求，请在系统设置的登录项中允许 TypeWhale"
            : "登录 macOS 后自动启动 TypeWhale"
    }

    @objc private func beginHotkeyCapture() {
        beginHotkeyCaptureForSlot(.primary)
    }

    @objc private func beginSecondaryHotkeyCapture() {
        beginHotkeyCaptureForSlot(.secondary)
    }

    private func beginHotkeyCaptureForSlot(_ slot: HotkeySlot) {
        guard !isCapturingHotkey else { return }
        isCapturingHotkey = true
        capturingChannel = .chinese
        capturingHotkeySlot = slot
        captureModifierKeyCodes.removeAll()
        activeHotkeyValueLabel?.stringValue = "请按快捷键…"
        activeHotkeyValueLabel?.textColor = .systemOrange
        hotkeyCaptureButton.isEnabled = false
        secondaryHotkeyCaptureButton.isEnabled = false
        startHotkeyCaptureTap()
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            self.capture(event: event)
            return nil
        }
    }

    @objc private func resetHotkey() {
        applyHotkey(.defaultBinding, slot: .primary, channel: .chinese)
    }

    @objc private func clearSecondaryHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: nil
        )
        onHotkeysChange?(
            HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            nil
        )
    }

    func updateHotkeys(primary: HotkeyBinding, secondary: HotkeyBinding?) {
        hotkeyValue.stringValue = primary.displayName
        hotkeyValue.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        secondaryHotkeyValue.stringValue = secondary?.displayName ?? "未设置"
        secondaryHotkeyValue.textColor = secondary == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        detail.stringValue = "\(primary.displayName) 录音"
    }

    func updateHotkey(_ binding: HotkeyBinding) {
        updateHotkeys(primary: binding, secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey))
    }

    private func startHotkeyCaptureTap() {
        stopHotkeyCaptureTap()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        hotkeyCaptureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<MainViewController>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = controller.hotkeyCaptureTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if controller.capture(event: event, type: type) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let hotkeyCaptureTap else { return }
        hotkeyCaptureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hotkeyCaptureTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), hotkeyCaptureSource, .commonModes)
        CGEvent.tapEnable(tap: hotkeyCaptureTap, enable: true)
    }

    private func stopHotkeyCaptureTap() {
        if let hotkeyCaptureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeyCaptureSource, .commonModes)
        }
        hotkeyCaptureSource = nil
        hotkeyCaptureTap = nil
    }

    private func capture(event: CGEvent, type: CGEventType) -> Bool {
        guard isCapturingHotkey else { return false }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            if keyCode == HotkeyKeyCodes.function || event.flags.contains(.maskSecondaryFn) {
                captureFunctionKey()
                return true
            }
            captureModifier(keyCode: keyCode, cgFlags: event.flags)
            return true
        }
        guard type == .keyDown else { return false }
        if keyCode == 53 {
            captureConfirmWorkItem?.cancel()
            endHotkeyCapture()
            refreshHotkeyLabels()
            return true
        }
        captureConfirmWorkItem?.cancel()
        if captureModifierKeyCodes.isEmpty {
            captureModifierKeyCodes = HotkeyKeyCodes.fallbackModifierKeyCodes(from: event.flags)
        }
        commitCapturedHotkey(keyCode: keyCode)
        return true
    }

    private func capture(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        if event.type == .flagsChanged {
            if keyCode == HotkeyKeyCodes.function || event.modifierFlags.contains(.function) {
                captureFunctionKey()
                return
            }
            captureModifier(keyCode: keyCode, modifierFlags: event.modifierFlags)
            return
        }

        if keyCode == 53 {
            captureConfirmWorkItem?.cancel()
            endHotkeyCapture()
            refreshHotkeyLabels()
            return
        }
        captureConfirmWorkItem?.cancel()
        if captureModifierKeyCodes.isEmpty {
            captureModifierKeyCodes = HotkeyKeyCodes.fallbackModifierKeyCodes(from: event.modifierFlags)
        }
        commitCapturedHotkey(keyCode: keyCode)
    }

    private func captureModifier(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.modifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && modifierFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    private func captureModifier(keyCode: Int, cgFlags: CGEventFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && cgFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    private func captureModifier(keyCode: Int, isPressed: Bool) {
        if isPressed {
            captureModifierKeyCodes.insert(keyCode)
            if capturingChannel != nil {
                activeHotkeyValueLabel?.stringValue = "\(HotkeyKeyCodes.displayName(for: keyCode)) …"
                activeHotkeyValueLabel?.textColor = .systemOrange
            }
            scheduleModifierCaptureConfirmation(keyCode: keyCode)
        } else {
            captureConfirmWorkItem?.cancel()
            commitCapturedHotkey(keyCode: keyCode)
        }
    }

    private func captureFunctionKey() {
        guard capturingChannel != nil else { return }
        activeHotkeyValueLabel?.stringValue = "Fn …"
        activeHotkeyValueLabel?.textColor = .systemOrange
        captureModifierKeyCodes = []
        commitCapturedHotkey(keyCode: HotkeyKeyCodes.function)
    }

    private func scheduleModifierCaptureConfirmation(keyCode: Int, delay: TimeInterval = 0.45) {
        captureConfirmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturingHotkey else { return }
            self.commitCapturedHotkey(keyCode: keyCode)
        }
        captureConfirmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func commitCapturedHotkey(keyCode: Int) {
        guard let capturingChannel else { return }
        guard let binding = HotkeyBinding.fromCapture(keyCode: keyCode, modifierKeyCodes: captureModifierKeyCodes) else {
            showCaptureError("请加 Cmd/Option/Control", channel: capturingChannel)
            return
        }
        applyCapturedHotkey(binding)
    }

    private func showCaptureError(_ message: String, channel: SpeechInputChannel) {
        captureConfirmWorkItem?.cancel()
        activeHotkeyValueLabel?.stringValue = message
        activeHotkeyValueLabel?.textColor = .systemRed
    }

    private func applyCapturedHotkey(_ binding: HotkeyBinding) {
        guard let capturingChannel, let capturingHotkeySlot else { return }
        applyHotkey(binding, slot: capturingHotkeySlot, channel: capturingChannel)
    }

    private func applyHotkey(_ binding: HotkeyBinding, slot: HotkeySlot, channel: SpeechInputChannel) {
        endHotkeyCapture()
        switch slot {
        case .primary:
            binding.save(storageKey: HotkeyBinding.chineseStorageKey)
        case .secondary:
            binding.save(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        }
        let primary = HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding)
        let secondary = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        updateHotkeys(primary: primary, secondary: secondary)
        onHotkeysChange?(primary, secondary)
    }

    private func endHotkeyCapture() {
        captureConfirmWorkItem?.cancel()
        captureConfirmWorkItem = nil
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
        }
        hotkeyCaptureMonitor = nil
        stopHotkeyCaptureTap()
        isCapturingHotkey = false
        capturingChannel = nil
        capturingHotkeySlot = nil
        hotkeyCaptureButton.isEnabled = true
        secondaryHotkeyCaptureButton.isEnabled = true
        captureModifierKeyCodes.removeAll()
    }

    private func refreshHotkeyLabels() {
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        )
    }

    private var activeHotkeyValueLabel: NSTextField? {
        switch capturingHotkeySlot {
        case .primary:
            return hotkeyValue
        case .secondary:
            return secondaryHotkeyValue
        case nil:
            return nil
        }
    }

    @objc private func installModel() {
        onInstallModel?()
    }

    func updateModelState(_ state: SenseVoiceModelInstaller.State) {
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
        if resetWaveform {
            resetInputBands()
        }
    }

    private func statusColor(for tone: PrimaryStatusTone) -> NSColor {
        switch tone {
        case .idle, .success:
            return .systemGreen
        case .listening, .processing:
            return UITheme.brandYellow
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    @objc private func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openKeyboard() {
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

    func addRecentTranscription(_ text: String, recognitionSeconds: Double) {
        guard !text.isEmpty else { return }
        let record = RecentTranscription(text: text, recognitionSeconds: recognitionSeconds)
        recentRecords.removeAll { $0.text == text }
        recentRecords.insert(record, at: 0)
        recentRecords = Array(recentRecords.prefix(5))
        saveRecentTranscriptions()
        rebuildRecentRows()
    }

    private func loadRecentTranscriptions() -> [RecentTranscription] {
        if let data = UserDefaults.standard.data(forKey: "recentTranscriptionRecords"),
           let records = try? JSONDecoder().decode([RecentTranscription].self, from: data) {
            return Array(records.prefix(5))
        }
        let legacy = UserDefaults.standard.stringArray(forKey: "recentTranscriptions") ?? []
        return Array(legacy.prefix(5)).map { RecentTranscription(text: $0, recognitionSeconds: nil) }
    }

    private func saveRecentTranscriptions() {
        if let data = try? JSONEncoder().encode(recentRecords) {
            UserDefaults.standard.set(data, forKey: "recentTranscriptionRecords")
        }
        UserDefaults.standard.set(recentRecords.map(\.text), forKey: "recentTranscriptions")
    }

    private func rebuildRecentRows() {
        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if recentRecords.isEmpty {
            let empty = label("尚无转录结果", size: 13)
            empty.textColor = .secondaryLabelColor
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            empty.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
                empty.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                empty.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            ])
            recentStack.addArrangedSubview(wrapper)
            return
        }
        for (index, record) in recentRecords.enumerated() {
            let metaLabel = label(record.timeText, size: 10, weight: .medium)
            metaLabel.textColor = .secondaryLabelColor
            metaLabel.maximumNumberOfLines = 1
            metaLabel.lineBreakMode = .byTruncatingTail
            metaLabel.translatesAutoresizingMaskIntoConstraints = false

            let textLabel = label(record.text, size: 12)
            textLabel.maximumNumberOfLines = 3
            textLabel.lineBreakMode = .byWordWrapping
            (textLabel.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
            textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textLabel.translatesAutoresizingMaskIntoConstraints = false

            let copyButton = NSButton()
            copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
            copyButton.bezelStyle = .inline
            copyButton.isBordered = false
            copyButton.toolTip = "复制"
            copyButton.tag = index
            copyButton.target = self
            copyButton.action = #selector(copyRecent(_:))
            copyButton.translatesAutoresizingMaskIntoConstraints = false

            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(metaLabel)
            row.addSubview(textLabel)
            row.addSubview(copyButton)
            recentStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: recentStack.widthAnchor),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
                metaLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                metaLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                metaLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                textLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                textLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 5),
                textLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -9),
                textLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                copyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                copyButton.widthAnchor.constraint(equalToConstant: 24),
                copyButton.heightAnchor.constraint(equalToConstant: 24),
            ])
            if index < recentRecords.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                    divider.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                    divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                ])
            }
        }
    }

    @objc private func copyRecent(_ sender: NSButton) {
        guard recentRecords.indices.contains(sender.tag) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recentRecords[sender.tag].text, forType: .string)
    }
}
