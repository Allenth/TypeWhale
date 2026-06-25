import AppKit
import ApplicationServices
import CoreGraphics

extension MainViewController {
    @objc func beginHotkeyCapture() {
        beginHotkeyCaptureForSlot(.primary)
    }

    @objc func beginSecondaryHotkeyCapture() {
        beginHotkeyCaptureForSlot(.secondary)
    }

    @objc func beginScreenshotHotkeyCapture() {
        beginHotkeyCaptureForSlot(.screenshot)
    }

    @objc func beginSecondaryScreenshotHotkeyCapture() {
        beginHotkeyCaptureForSlot(.screenshotSecondary)
    }

    @objc func beginScreenshotTranslationHotkeyCapture() {
        beginHotkeyCaptureForSlot(.screenshotTranslation)
    }

    @objc func beginAutoTranslateHotkeyCapture() {
        beginHotkeyCaptureForSlot(.autoTranslate)
    }

    @objc func beginMainWindowHotkeyCapture() {
        beginHotkeyCaptureForSlot(.mainWindow)
    }

    func beginHotkeyCaptureForSlot(_ slot: HotkeySlot) {
        guard !isCapturingHotkey else { return }
        isCapturingHotkey = true
        capturingChannel = .chinese
        capturingHotkeySlot = slot
        captureModifierKeyCodes.removeAll()
        activeHotkeyButton?.title = "请按快捷键或耳机播放键…"
        hotkeyCaptureButton.isEnabled = false
        secondaryHotkeyCaptureButton.isEnabled = false
        screenshotHotkeyCaptureButton.isEnabled = false
        secondaryScreenshotHotkeyCaptureButton.isEnabled = false
        screenshotTranslationHotkeyCaptureButton.isEnabled = false
        autoTranslateHotkeyCaptureButton.isEnabled = false
        mainWindowHotkeyCaptureButton.isEnabled = false
        startHotkeyCaptureTap()
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            self.capture(event: event)
            return nil
        }
    }

    @objc func resetHotkey() {
        applyHotkey(.defaultBinding, slot: .primary, channel: .chinese)
    }

    @objc func resetScreenshotHotkey() {
        applyHotkey(.screenshotDefaultBinding, slot: .screenshot, channel: .chinese)
    }

    @objc func resetScreenshotTranslationHotkey() {
        applyHotkey(.screenshotTranslationDefaultBinding, slot: .screenshotTranslation, channel: .chinese)
    }

    @objc func clearSecondaryScreenshotHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.secondaryScreenshotStorageKey)
        refreshHotkeyLabels()
        emitHotkeysChange()
    }

    @objc func clearMainWindowHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.mainWindowStorageKey)
        refreshHotkeyLabels()
        emitHotkeysChange()
    }

    @objc func clearAutoTranslateHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.autoTranslateStorageKey)
        refreshHotkeyLabels()
        emitHotkeysChange()
    }

    @objc func clearSecondaryHotkey() {
        endHotkeyCapture()
        HotkeyBinding.clear(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: nil,
            screenshot: HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding),
            secondaryScreenshot: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey),
            screenshotTranslation: HotkeyBinding.load(
                storageKey: HotkeyBinding.screenshotTranslationStorageKey,
                fallback: .screenshotTranslationDefaultBinding
            ),
            autoTranslate: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey),
            mainWindow: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
        )
        emitHotkeysChange()
    }

    func updateHotkeys(
        primary: HotkeyBinding,
        secondary: HotkeyBinding?,
        screenshot: HotkeyBinding,
        secondaryScreenshot: HotkeyBinding?,
        screenshotTranslation: HotkeyBinding,
        autoTranslate: HotkeyBinding?,
        mainWindow: HotkeyBinding?
    ) {
        hotkeyValue.stringValue = primary.displayName
        hotkeyValue.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        hotkeyCaptureButton.title = primary.displayName
        hotkeyCaptureButton.toolTip = "点击录入主快捷键"
        secondaryHotkeyValue.stringValue = secondary?.displayName ?? "未设置"
        secondaryHotkeyValue.textColor = secondary == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        secondaryHotkeyCaptureButton.title = secondary?.displayName ?? "未设置"
        secondaryHotkeyCaptureButton.toolTip = "点击录入备用快捷键"
        screenshotHotkeyValue.stringValue = screenshot.screenshotDisplayName
        screenshotHotkeyValue.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        screenshotHotkeyCaptureButton.title = screenshot.screenshotDisplayName
        screenshotHotkeyCaptureButton.toolTip = "点击录入截图快捷键：双击修饰键、修饰键+按键组合，或耳机播放键"
        secondaryScreenshotHotkeyValue.stringValue = secondaryScreenshot?.screenshotDisplayName ?? "未设置"
        secondaryScreenshotHotkeyValue.textColor = secondaryScreenshot == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        secondaryScreenshotHotkeyCaptureButton.title = secondaryScreenshot?.screenshotDisplayName ?? "未设置"
        secondaryScreenshotHotkeyCaptureButton.toolTip = "点击录入截图备用快捷键"
        screenshotTranslationHotkeyValue.stringValue = screenshotTranslation.screenshotDisplayName
        screenshotTranslationHotkeyValue.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        screenshotTranslationHotkeyCaptureButton.title = screenshotTranslation.screenshotDisplayName
        screenshotTranslationHotkeyCaptureButton.toolTip = "点击录入翻译截图快捷键：双击修饰键、修饰键+按键组合，或耳机播放键"
        autoTranslateHotkeyValue.stringValue = autoTranslate?.actionDisplayName ?? "未设置"
        autoTranslateHotkeyValue.textColor = autoTranslate == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        autoTranslateHotkeyCaptureButton.title = autoTranslate?.actionDisplayName ?? "未设置"
        autoTranslateHotkeyCaptureButton.toolTip = "点击录入自动翻译开关快捷键，可使用耳机播放键"
        mainWindowHotkeyValue.stringValue = mainWindow?.actionDisplayName ?? "未设置"
        mainWindowHotkeyValue.textColor = mainWindow == nil ? .tertiaryLabelColor : NSColor(calibratedWhite: 1, alpha: 0.92)
        mainWindowHotkeyCaptureButton.title = mainWindow?.actionDisplayName ?? "未设置"
        mainWindowHotkeyCaptureButton.toolTip = "点击录入唤起主页快捷键，可使用耳机播放键"
        detail.stringValue = "\(primary.displayName) 录音"
    }

    func updateHotkey(_ binding: HotkeyBinding) {
        updateHotkeys(
            primary: binding,
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey),
            screenshot: HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding),
            secondaryScreenshot: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey),
            screenshotTranslation: HotkeyBinding.load(
                storageKey: HotkeyBinding.screenshotTranslationStorageKey,
                fallback: .screenshotTranslationDefaultBinding
            ),
            autoTranslate: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey),
            mainWindow: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
        )
    }

    func startHotkeyCaptureTap() {
        stopHotkeyCaptureTap()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << MediaKeyCapture.systemDefinedEventType.rawValue)
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

    func stopHotkeyCaptureTap() {
        if let hotkeyCaptureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeyCaptureSource, .commonModes)
        }
        hotkeyCaptureSource = nil
        hotkeyCaptureTap = nil
    }

    func capture(event: CGEvent, type: CGEventType) -> Bool {
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
        if type == MediaKeyCapture.systemDefinedEventType, captureMediaPlay(event: event) {
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

    func capture(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        if event.type == .systemDefined, captureMediaPlay(event: event) {
            return
        }
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

    func captureModifier(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.modifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && modifierFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    func captureModifier(keyCode: Int, cgFlags: CGEventFlags) {
        guard HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let modifierFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
        let isPressed = !modifierFlag.isEmpty && cgFlags.contains(modifierFlag)
        captureModifier(keyCode: keyCode, isPressed: isPressed)
    }

    func captureModifier(keyCode: Int, isPressed: Bool) {
        if isPressed {
            captureModifierKeyCodes.insert(keyCode)
            if capturingChannel != nil {
                activeHotkeyButton?.title = "\(HotkeyKeyCodes.displayName(for: keyCode)) …"
            }
            scheduleModifierCaptureConfirmation(keyCode: keyCode)
        } else {
            captureConfirmWorkItem?.cancel()
            commitCapturedHotkey(keyCode: keyCode)
        }
    }

    func captureFunctionKey() {
        guard capturingChannel != nil else { return }
        activeHotkeyButton?.title = "Fn …"
        captureModifierKeyCodes = []
        commitCapturedHotkey(keyCode: HotkeyKeyCodes.function)
    }

    func captureMediaPlay(event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }
        return captureMediaPlay(event: nsEvent)
    }

    func captureMediaPlay(event: NSEvent) -> Bool {
        guard isMediaPlayDown(event) else { return false }
        captureConfirmWorkItem?.cancel()
        activeHotkeyButton?.title = "耳机播放键 …"
        captureModifierKeyCodes = []
        applyCapturedHotkey(.mediaPlayBinding)
        return true
    }

    func isMediaPlayDown(_ event: NSEvent) -> Bool {
        guard event.type == .systemDefined,
              event.subtype.rawValue == MediaKeyCapture.auxControlButtonSubtype else {
            return false
        }
        let data = event.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyState = (data & 0x0000FF00) >> 8
        return keyCode == MediaKeyCapture.play && keyState == MediaKeyCapture.keyDownState
    }

    func scheduleModifierCaptureConfirmation(keyCode: Int, delay: TimeInterval = 0.45) {
        captureConfirmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturingHotkey else { return }
            self.commitCapturedHotkey(keyCode: keyCode)
        }
        captureConfirmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func commitCapturedHotkey(keyCode: Int) {
        guard let capturingChannel else { return }
        guard let binding = HotkeyBinding.fromCapture(keyCode: keyCode, modifierKeyCodes: captureModifierKeyCodes) else {
            showCaptureError("请加 Cmd/Option/Control", channel: capturingChannel)
            return
        }
        applyCapturedHotkey(binding)
    }

    func showCaptureError(_ message: String, channel: SpeechInputChannel) {
        captureConfirmWorkItem?.cancel()
        activeHotkeyButton?.title = message
    }

    func applyCapturedHotkey(_ binding: HotkeyBinding) {
        guard let capturingChannel, let capturingHotkeySlot else { return }
        applyHotkey(binding, slot: capturingHotkeySlot, channel: capturingChannel)
    }

    func applyHotkey(_ binding: HotkeyBinding, slot: HotkeySlot, channel: SpeechInputChannel) {
        endHotkeyCapture()
        switch slot {
        case .primary:
            binding.save(storageKey: HotkeyBinding.chineseStorageKey)
        case .secondary:
            binding.save(storageKey: HotkeyBinding.secondaryChineseStorageKey)
        case .screenshot:
            binding.save(storageKey: HotkeyBinding.screenshotStorageKey)
        case .screenshotSecondary:
            binding.save(storageKey: HotkeyBinding.secondaryScreenshotStorageKey)
        case .screenshotTranslation:
            binding.save(storageKey: HotkeyBinding.screenshotTranslationStorageKey)
        case .autoTranslate:
            binding.save(storageKey: HotkeyBinding.autoTranslateStorageKey)
        case .mainWindow:
            binding.save(storageKey: HotkeyBinding.mainWindowStorageKey)
        }
        refreshHotkeyLabels()
        emitHotkeysChange()
    }

    func endHotkeyCapture() {
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
        screenshotHotkeyCaptureButton.isEnabled = true
        secondaryScreenshotHotkeyCaptureButton.isEnabled = true
        screenshotTranslationHotkeyCaptureButton.isEnabled = true
        autoTranslateHotkeyCaptureButton.isEnabled = true
        mainWindowHotkeyCaptureButton.isEnabled = true
        captureModifierKeyCodes.removeAll()
    }

    func refreshHotkeyLabels() {
        updateHotkeys(
            primary: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            secondary: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey),
            screenshot: HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding),
            secondaryScreenshot: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey),
            screenshotTranslation: HotkeyBinding.load(
                storageKey: HotkeyBinding.screenshotTranslationStorageKey,
                fallback: .screenshotTranslationDefaultBinding
            ),
            autoTranslate: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey),
            mainWindow: HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
        )
    }

    func emitHotkeysChange() {
        onHotkeysChange?(
            HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
            HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryChineseStorageKey),
            HotkeyBinding.load(storageKey: HotkeyBinding.screenshotStorageKey, fallback: .screenshotDefaultBinding),
            HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey),
            HotkeyBinding.load(
                storageKey: HotkeyBinding.screenshotTranslationStorageKey,
                fallback: .screenshotTranslationDefaultBinding
            ),
            HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey),
            HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
        )
    }

    var activeHotkeyButton: NSButton? {
        switch capturingHotkeySlot {
        case .primary:
            return hotkeyCaptureButton
        case .secondary:
            return secondaryHotkeyCaptureButton
        case .screenshot:
            return screenshotHotkeyCaptureButton
        case .screenshotSecondary:
            return secondaryScreenshotHotkeyCaptureButton
        case .screenshotTranslation:
            return screenshotTranslationHotkeyCaptureButton
        case .autoTranslate:
            return autoTranslateHotkeyCaptureButton
        case .mainWindow:
            return mainWindowHotkeyCaptureButton
        case nil:
            return nil
        }
    }
}
