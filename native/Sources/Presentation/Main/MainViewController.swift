import AppKit
import ApplicationServices

final class MainViewController: NSViewController {
    private let contentWidth: CGFloat = 560
    private let contentHeight: CGFloat = 852
    private let pageInset: CGFloat = 24
    private let recentViewportHeight: CGFloat = 250
    private let brandIconVisibleSize: CGFloat = 94

    let status = label("等待录音", size: 18, weight: .semibold)
    let detail = label("Fn 录音", size: 12)
    let micStatus = label("检测中", size: 12, weight: .medium)
    let accessibilityStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyStatus = label("检测中", size: 12, weight: .medium)
    let hotkeyValue = label(
        HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding).displayName,
        size: 13,
        weight: .medium
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
    let modelValue = label("正在检查模型", size: 13, weight: .medium)
    let modelProgress = NSProgressIndicator()
    let modelInstallButton = NSButton(title: "安装模型", target: nil, action: nil)
    let realtime = NSButton(checkboxWithTitle: "胶囊实时预览", target: nil, action: nil)
    let autoFinish = NSButton(checkboxWithTitle: "停顿自动完成", target: nil, action: nil)
    let duckSystemAudio = NSButton(checkboxWithTitle: "录音时降低电脑声音", target: nil, action: nil)
    let launchAtLogin = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    let realtimeDraft = label("等待实时草稿", size: 13)
    var onInstallModel: (() -> Void)?
    var onHotkeysChange: ((HotkeyBinding, HotkeyBinding?) -> Void)?
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
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.18).cgColor
        view = root
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: contentWidth),
            view.heightAnchor.constraint(equalToConstant: contentHeight),
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

        let brandIcon = NSImageView()
        brandIcon.image = loadBrandIcon()
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.wantsLayer = true
        brandIcon.layer?.cornerRadius = 18
        brandIcon.layer?.masksToBounds = true
        let brandTitle = label("TypeWhale", size: 18, weight: .semibold)
        brandTitle.maximumNumberOfLines = 1
        brandTitle.lineBreakMode = .byClipping
        brandTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        let brandVersion = label(versionText(), size: 12, weight: .medium)
        brandVersion.textColor = .secondaryLabelColor
        brandVersion.maximumNumberOfLines = 1
        brandVersion.lineBreakMode = .byClipping
        brandVersion.setContentCompressionResistancePriority(.required, for: .vertical)
        let versionHelpButton = NSButton(title: "?", target: self, action: #selector(showVersionHistory(_:)))
        versionHelpButton.bezelStyle = .circular
        versionHelpButton.controlSize = .small
        versionHelpButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        versionHelpButton.toolTip = "查看版本历史"
        versionHelpButton.translatesAutoresizingMaskIntoConstraints = false
        let versionRow = NSStackView(views: [brandVersion, versionHelpButton])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 6
        versionRow.setContentCompressionResistancePriority(.required, for: .vertical)
        let brandText = NSStackView(views: [brandTitle, versionRow])
        brandText.orientation = .vertical
        brandText.alignment = .leading
        brandText.spacing = 3
        brandText.setContentCompressionResistancePriority(.required, for: .vertical)
        let brandRow = NSStackView(views: [brandIcon, brandText])
        brandRow.orientation = .horizontal
        brandRow.alignment = .centerY
        brandRow.spacing = 24
        brandRow.setContentHuggingPriority(.required, for: .vertical)
        brandRow.setContentCompressionResistancePriority(.required, for: .vertical)
        status.alignment = .right
        status.maximumNumberOfLines = 1
        status.lineBreakMode = .byTruncatingTail
        detail.alignment = .right
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        detail.textColor = .secondaryLabelColor
        let statusBlock = NSStackView(views: [status, detail])
        statusBlock.orientation = .vertical
        statusBlock.alignment = .trailing
        statusBlock.spacing = 6
        statusBlock.setContentHuggingPriority(.required, for: .vertical)
        statusBlock.setContentCompressionResistancePriority(.required, for: .vertical)
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerRow = NSStackView(views: [brandRow, headerSpacer, statusBlock])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 16
        headerRow.setContentHuggingPriority(.required, for: .vertical)
        headerRow.setContentCompressionResistancePriority(.required, for: .vertical)

        let permissionTitle = label("权限", size: 14, weight: .semibold)
        let micButton = NSButton(title: "麦克风设置", target: self, action: #selector(openMicrophone))
        let accessButton = NSButton(title: "辅助功能设置", target: self, action: #selector(openAccessibility))
        let keyboardButton = NSButton(title: "键盘设置", target: self, action: #selector(openKeyboard))
        let micName = label("麦克风", size: 13)
        let accessName = label("辅助功能", size: 13)
        let hotkeyName = label("全局快捷键", size: 13)
        let hotkeyBindingName = label("主快捷键", size: 13)
        let secondaryHotkeyBindingName = label("备用快捷键", size: 13)
        let micRow = NSStackView(views: [micName, micStatus, micButton])
        let accessRow = NSStackView(views: [accessName, accessibilityStatus, accessButton])
        let hotkeyRow = NSStackView(views: [hotkeyName, hotkeyStatus, keyboardButton])
        [hotkeyValue, secondaryHotkeyValue].forEach {
            $0.textColor = .secondaryLabelColor
            $0.lineBreakMode = .byTruncatingMiddle
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        hotkeyCaptureButton.target = self
        hotkeyCaptureButton.action = #selector(beginHotkeyCapture)
        hotkeyResetButton.target = self
        hotkeyResetButton.action = #selector(resetHotkey)
        secondaryHotkeyCaptureButton.target = self
        secondaryHotkeyCaptureButton.action = #selector(beginSecondaryHotkeyCapture)
        secondaryHotkeyClearButton.target = self
        secondaryHotkeyClearButton.action = #selector(clearSecondaryHotkey)
        let hotkeyBindingRow = NSStackView(views: [hotkeyBindingName, hotkeyValue, hotkeyCaptureButton, hotkeyResetButton])
        let secondaryHotkeyBindingRow = NSStackView(views: [secondaryHotkeyBindingName, secondaryHotkeyValue, secondaryHotkeyCaptureButton, secondaryHotkeyClearButton])
        [micRow, accessRow, hotkeyRow, hotkeyBindingRow, secondaryHotkeyBindingRow].forEach {
            $0.orientation = .horizontal
            $0.alignment = .centerY
            $0.distribution = .fill
            $0.spacing = 12
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        [micName, accessName, hotkeyName, hotkeyBindingName, secondaryHotkeyBindingName].forEach {
            $0.widthAnchor.constraint(equalToConstant: 90).isActive = true
        }
        [micStatus, accessibilityStatus, hotkeyStatus].forEach {
            $0.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }
        [micButton, accessButton, keyboardButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: 130).isActive = true
        }
        [hotkeyValue, secondaryHotkeyValue].forEach {
            $0.widthAnchor.constraint(equalToConstant: 150).isActive = true
        }
        [hotkeyCaptureButton, secondaryHotkeyCaptureButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: 72).isActive = true
        }
        hotkeyResetButton.widthAnchor.constraint(equalToConstant: 118).isActive = true
        secondaryHotkeyClearButton.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let modelTitle = label("本地识别模型", size: 14, weight: .semibold)
        modelValue.textColor = .secondaryLabelColor
        modelValue.maximumNumberOfLines = 2
        modelValue.lineBreakMode = .byWordWrapping
        modelValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelProgress.isIndeterminate = false
        modelProgress.minValue = 0
        modelProgress.maxValue = 1
        modelProgress.controlSize = .small
        modelProgress.isHidden = true
        modelInstallButton.target = self
        modelInstallButton.action = #selector(installModel)
        modelInstallButton.isHidden = true
        modelInstallButton.widthAnchor.constraint(equalToConstant: 94).isActive = true
        let modelSpacer = NSView()
        modelSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let modelRow = NSStackView(views: [modelValue, modelSpacer, modelInstallButton])
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 10
        let modelTitleSpacer = NSView()
        modelTitleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let modelTitleRow = NSStackView(views: [modelTitle, modelTitleSpacer])
        modelTitleRow.orientation = .horizontal
        modelTitleRow.alignment = .centerY
        modelTitleRow.spacing = 12
        modelTitleRow.setContentHuggingPriority(.required, for: .vertical)
        modelTitleRow.setContentCompressionResistancePriority(.required, for: .vertical)
        let modelSettingsSpacer = NSView()
        modelSettingsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let modelSettingsRow = NSStackView(views: [modelSettingsSpacer, launchAtLogin, duckSystemAudio, autoFinish, realtime])
        modelSettingsRow.orientation = .horizontal
        modelSettingsRow.alignment = .centerY
        modelSettingsRow.spacing = 12
        modelSettingsRow.setContentHuggingPriority(.required, for: .vertical)
        modelSettingsRow.setContentCompressionResistancePriority(.required, for: .vertical)
        realtimeDraft.maximumNumberOfLines = 2
        realtimeDraft.lineBreakMode = .byWordWrapping
        (realtimeDraft.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        realtimeDraft.textColor = .secondaryLabelColor
        realtimeDraft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        realtimeDraft.setContentHuggingPriority(.defaultLow, for: .vertical)
        let guideTitle = label("使用说明", size: 14, weight: .semibold)
        let guideText = label("授权麦克风和辅助功能后，按主快捷键开始录音，再次按下停止；也可以按住说话、松开粘贴。备用快捷键可作为第二个入口。", size: 12)
        guideText.textColor = .secondaryLabelColor
        guideText.maximumNumberOfLines = 2
        guideText.lineBreakMode = .byWordWrapping
        guideText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        guideText.setContentCompressionResistancePriority(.required, for: .vertical)
        let resultTitle = label("最近转录", size: 14, weight: .semibold)
        resultTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        recentStack.orientation = .vertical
        recentStack.alignment = .width
        recentStack.spacing = 0
        recentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentRecords = loadRecentTranscriptions()
        rebuildRecentRows()
        recentScroll.documentView = recentStack
        recentScroll.hasVerticalScroller = true
        recentScroll.autohidesScrollers = true
        recentScroll.drawsBackground = false
        recentScroll.borderType = .noBorder
        recentScroll.setContentHuggingPriority(.required, for: .vertical)
        recentScroll.setContentCompressionResistancePriority(.required, for: .vertical)

        let topSeparator = separator()
        let permissionSeparator = separator()
        let guideSeparator = separator()
        let resultSeparator = separator()
        let stack = NSStackView(views: [
            headerRow, topSeparator, guideTitle, guideText,
            guideSeparator, permissionTitle, micRow, accessRow, hotkeyRow, hotkeyBindingRow, secondaryHotkeyBindingRow,
            permissionSeparator, modelTitleRow, modelSettingsRow, modelRow, modelProgress, realtimeDraft,
            resultSeparator, resultTitle, recentScroll,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pageInset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pageInset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            brandRow.heightAnchor.constraint(greaterThanOrEqualToConstant: brandIconVisibleSize),
            brandIcon.widthAnchor.constraint(equalToConstant: brandIconVisibleSize),
            brandIcon.heightAnchor.constraint(equalToConstant: brandIconVisibleSize),
            brandTitle.heightAnchor.constraint(equalToConstant: 22),
            brandVersion.heightAnchor.constraint(equalToConstant: 16),
            versionHelpButton.widthAnchor.constraint(equalToConstant: 20),
            versionHelpButton.heightAnchor.constraint(equalToConstant: 20),
            statusBlock.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            topSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guideSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resultSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guideTitle.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            permissionTitle.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            modelTitleRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            modelSettingsRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            resultTitle.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            micRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            accessRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotkeyRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotkeyBindingRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryHotkeyBindingRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelTitleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelSettingsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelProgress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recentScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recentScroll.heightAnchor.constraint(equalToConstant: recentViewportHeight),
            recentScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pageInset),
            recentStack.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor),
            realtimeDraft.widthAnchor.constraint(equalTo: stack.widthAnchor),
            realtimeDraft.heightAnchor.constraint(equalToConstant: 34),
            guideText.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guideText.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            micRow.heightAnchor.constraint(equalToConstant: 32),
            accessRow.heightAnchor.constraint(equalToConstant: 32),
            hotkeyRow.heightAnchor.constraint(equalToConstant: 32),
            hotkeyBindingRow.heightAnchor.constraint(equalToConstant: 32),
            secondaryHotkeyBindingRow.heightAnchor.constraint(equalToConstant: 32),
        ])
        DispatchQueue.main.async { [weak self] in
            _ = self?.versionHistoryViewController.view
        }
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.12"
        let build = info?["CFBundleVersion"] as? String ?? "169"
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
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func saveSettings() {
        if autoFinish.state == .on {
            realtime.state = .on
        }
        if realtime.state == .off {
            autoFinish.state = .off
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
        hotkeyValue.textColor = .secondaryLabelColor
        secondaryHotkeyValue.stringValue = secondary?.displayName ?? "未设置"
        secondaryHotkeyValue.textColor = .secondaryLabelColor
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
            modelValue.toolTip = nil
            modelValue.stringValue = "SenseVoice int8 缺失"
            modelValue.textColor = .systemRed
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "安装模型"
        case .ready:
            let sensePath = SenseVoiceModelManifest.preferredModelDirectory?.path ?? ""
            modelValue.toolTip = sensePath
            modelValue.stringValue = "SenseVoice int8 已就绪"
            modelValue.textColor = .systemGreen
            modelProgress.isHidden = true
            modelInstallButton.isHidden = true
        case .downloading(let progress):
            modelValue.toolTip = nil
            modelValue.stringValue = "正在安装 SenseVoice · \(Int(progress * 100))%"
            modelValue.textColor = .secondaryLabelColor
            modelProgress.doubleValue = progress
            modelProgress.isHidden = false
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = false
            modelInstallButton.title = "安装中"
        case .failed(let message):
            modelValue.toolTip = message
            modelValue.stringValue = message
            modelValue.textColor = .systemRed
            modelProgress.isHidden = true
            modelInstallButton.isHidden = false
            modelInstallButton.isEnabled = true
            modelInstallButton.title = "重试安装"
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
            recentStack.addArrangedSubview(label("尚无转录结果", size: 13))
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
