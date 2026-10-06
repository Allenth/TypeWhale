import AppKit
import ApplicationServices
import Foundation

extension Notification.Name {
    static let typeWhaleMouseShortcutHandlingSuspensionDidChange = Notification.Name(
        "TypeWhale.mouseShortcutHandlingSuspensionDidChange"
    )
}

final class HotkeyMonitor {
    private struct SpeechBindingTarget {
        let channel: SpeechInputChannel
        let purpose: SpeechInputPurpose
        let binding: HotkeyBinding
    }

    private enum MediaKey {
        static let systemDefinedEventType = CGEventType(rawValue: 14)!
        static let auxControlButtonSubtype = 8
        static let play = 16
        static let keyDownState = 0x0A
    }

    private enum Timing {
        static let screenshotDoubleTapWindowSeconds: TimeInterval = 0.42
        static let actionTapWindowSeconds: TimeInterval = 0.42
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var mouseTap: CFMachPort?
    private var mouseSource: CFRunLoopSource?
    private var mouseShortcutHandlingSuspensionObserver: NSObjectProtocol?
    private var isMouseShortcutHandlingSuspended = false
    private var bindings = [
        SpeechBindingTarget(
            channel: .chinese,
            purpose: .dictation,
            binding: HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding)
        ),
    ]
    private var screenshotBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.screenshotStorageKey,
        fallback: .screenshotDefaultBinding
    )
    private var secondaryScreenshotBinding = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.secondaryScreenshotStorageKey)
    private var screenshotTranslationBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.screenshotTranslationStorageKey,
        fallback: .screenshotTranslationDefaultBinding
    )
    private var autoTranslateBinding = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.autoTranslateStorageKey)
    private var mainWindowBinding = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.mainWindowStorageKey)
    private var ideaPillBinding = HotkeyBinding.loadOptional(storageKey: HotkeyBinding.ideaPillStorageKey)
    private var openClawBinding = HotkeyBinding.loadOpenClaw()
    private var activeModifierKeyCodes: Set<Int> = []
    private var triggerDown = false
    private var screenshotTriggerDown = false
    private var secondaryScreenshotTriggerDown = false
    private var screenshotTranslationTriggerDown = false
    private var autoTranslateTriggerDown = false
    private var mainWindowTriggerDown = false
    private var lastScreenshotTapAt: Date?
    private var lastSecondaryScreenshotTapAt: Date?
    private var lastScreenshotTranslationTapAt: Date?
    private var actionTapState: [String: (count: Int, lastAt: Date)] = [:]
    private var activeChannel: SpeechInputChannel?
    private var activePurpose: SpeechInputPurpose?
    private var activeBinding: HotkeyBinding?
    private var escapeCancellationGate = EscapeCancellationGate()
    private var rightMouseCancellationGate = RightMouseCancellationGate()
    var onDown: ((SpeechInputChannel, SpeechInputPurpose, HotkeyBinding) -> Void)?
    var onUp: ((SpeechInputChannel, SpeechInputPurpose, HotkeyBinding) -> Void)?
    var onTimedDown: ((SpeechInputChannel, SpeechInputPurpose, HotkeyBinding, HotkeyEventTiming) -> Void)?
    var onTimedUp: ((SpeechInputChannel, SpeechInputPurpose, HotkeyBinding, HotkeyEventTiming) -> Void)?
    var onEscape: (() -> Bool)?
    var onRightMouse: (() -> Bool)?
    var onManualSubmitKey: (() -> Void)?
    var onAutoTranslateToggle: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onScreenshotTranslation: (() -> Void)?
    var onMainWindow: (() -> Void)?

    init() {
        mouseShortcutHandlingSuspensionObserver = NotificationCenter.default.addObserver(
            forName: .typeWhaleMouseShortcutHandlingSuspensionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.isMouseShortcutHandlingSuspended = notification.object as? Bool ?? false
        }
    }

    deinit {
        if let mouseShortcutHandlingSuspensionObserver {
            NotificationCenter.default.removeObserver(mouseShortcutHandlingSuspensionObserver)
        }
        stopEventTap()
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil || !isTapEnabled || mouseTap == nil || !isMouseTapEnabled else { return true }
        stopEventTap()
        let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let keyUpMask = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let mediaKeyMask = CGEventMask(1 << MediaKey.systemDefinedEventType.rawValue)
        let mask = flagsChangedMask |
            keyDownMask |
            keyUpMask |
            mediaKeyMask
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.reenableEventTap()
                } else if type == .flagsChanged {
                    if monitor.handleFlagsChanged(event: event) {
                        return nil
                    }
                } else if type == .keyDown || type == .keyUp {
                    if monitor.handleKey(event: event, isDown: type == .keyDown) {
                        return nil
                    }
                } else if type == MediaKey.systemDefinedEventType {
                    if monitor.handleSystemDefined(event: event) {
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let tap else {
            LaunchDiagnostics.mark("hotkey_tap_create_failed accessibility_trusted=\(AXIsProcessTrusted())")
            return false
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let enabled = CGEvent.tapIsEnabled(tap: tap)
        let mouseEnabled = startMouseEventTap(context: context)
        LaunchDiagnostics.mark("hotkey_tap_started enabled=\(enabled) mouse_enabled=\(mouseEnabled) accessibility_trusted=\(AXIsProcessTrusted())")
        return enabled && mouseEnabled
    }

    var isGlobalListening: Bool {
        isTapEnabled && isMouseTapEnabled
    }

    private var isTapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private var isMouseTapEnabled: Bool {
        guard let mouseTap else { return false }
        return CGEvent.tapIsEnabled(tap: mouseTap)
    }

    func update(_ binding: HotkeyBinding) {
        update(primary: binding, secondary: nil)
    }

    func update(primary: HotkeyBinding, secondary: HotkeyBinding?) {
        update(
            primary: primary,
            secondary: secondary,
            screenshot: screenshotBinding,
            secondaryScreenshot: secondaryScreenshotBinding,
            screenshotTranslation: screenshotTranslationBinding,
            autoTranslate: autoTranslateBinding,
            mainWindow: mainWindowBinding,
            ideaPill: ideaPillBinding,
            openClaw: openClawBinding
        )
    }

    func update(
        primary: HotkeyBinding,
        secondary: HotkeyBinding?,
        screenshot: HotkeyBinding,
        secondaryScreenshot: HotkeyBinding? = nil,
        screenshotTranslation: HotkeyBinding,
        autoTranslate: HotkeyBinding? = nil,
        mainWindow: HotkeyBinding? = nil,
        ideaPill: HotkeyBinding? = nil,
        openClaw: HotkeyBinding? = nil
    ) {
        self.bindings = [
            SpeechBindingTarget(channel: .chinese, purpose: .dictation, binding: primary),
        ] + (secondary.map {
            [SpeechBindingTarget(channel: .chinese, purpose: .dictation, binding: $0)]
        } ?? []) + (ideaPill.map {
            [SpeechBindingTarget(channel: .chinese, purpose: .ideaPill, binding: $0)]
        } ?? []) + (openClaw.map {
            [SpeechBindingTarget(channel: .chinese, purpose: .openClawChat, binding: $0)]
        } ?? [])
        self.screenshotBinding = screenshot
        self.secondaryScreenshotBinding = secondaryScreenshot
        self.screenshotTranslationBinding = screenshotTranslation
        self.autoTranslateBinding = autoTranslate
        self.mainWindowBinding = mainWindow
        self.ideaPillBinding = ideaPill
        self.openClawBinding = openClaw
        activeModifierKeyCodes.removeAll()
        triggerDown = false
        screenshotTriggerDown = false
        secondaryScreenshotTriggerDown = false
        screenshotTranslationTriggerDown = false
        autoTranslateTriggerDown = false
        mainWindowTriggerDown = false
        lastScreenshotTapAt = nil
        lastSecondaryScreenshotTapAt = nil
        lastScreenshotTranslationTapAt = nil
        actionTapState.removeAll()
        activeChannel = nil
        activePurpose = nil
        activeBinding = nil
    }

    private func reenableEventTap() {
        rightMouseCancellationGate.reset()
        RemoteMappedEventSuppressionRegistry.shared.reset()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: true)
        }
    }

    private func stopEventTap() {
        rightMouseCancellationGate.reset()
        RemoteMappedEventSuppressionRegistry.shared.reset()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let mouseSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseSource, .commonModes)
        }
        source = nil
        tap = nil
        mouseSource = nil
        mouseTap = nil
    }

    private func startMouseEventTap(context: UnsafeMutableRawPointer) -> Bool {
        let leftMouseDownMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let leftMouseUpMask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let rightMouseDownMask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let rightMouseUpMask = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let otherMouseDownMask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let otherMouseUpMask = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let mouseMask = leftMouseDownMask |
            leftMouseUpMask |
            rightMouseDownMask |
            rightMouseUpMask |
            otherMouseDownMask |
            otherMouseUpMask
        mouseTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mouseMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.reenableEventTap()
                } else if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                    if monitor.handleRightMouseCancellation(event: event, isDown: true) {
                        return nil
                    }
                    if !monitor.isMouseShortcutHandlingSuspended,
                       monitor.handleMouse(event: event, isDown: true) {
                        return nil
                    }
                } else if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
                    if monitor.handleRightMouseCancellation(event: event, isDown: false) {
                        return nil
                    }
                    if !monitor.isMouseShortcutHandlingSuspended,
                       monitor.handleMouse(event: event, isDown: false) {
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let mouseTap else {
            LaunchDiagnostics.mark("hotkey_mouse_tap_create_failed accessibility_trusted=\(AXIsProcessTrusted())")
            return false
        }
        mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), mouseSource, .commonModes)
        CGEvent.tapEnable(tap: mouseTap, enable: true)
        return CGEvent.tapIsEnabled(tap: mouseTap)
    }

    private func handleRightMouseCancellation(event: CGEvent, isDown: Bool) -> Bool {
        rightMouseCancellationGate.handle(
            buttonNumber: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
            isDown: isDown,
            cancel: { [weak self] in self?.onRightMouse?() ?? false }
        )
    }

    func handleFlagsChanged(event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags
        if HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) {
            let keyFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
            if !keyFlag.isEmpty, eventFlags.contains(keyFlag) {
                activeModifierKeyCodes.insert(keyCode)
            } else {
                activeModifierKeyCodes.remove(keyCode)
            }
        }
        if handleScreenshotFlagsChanged(
            binding: screenshotBinding,
            keyCode: keyCode,
            eventFlags: eventFlags,
            triggerDown: &screenshotTriggerDown,
            lastTapAt: &lastScreenshotTapAt,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }
        if handleScreenshotFlagsChanged(
            binding: secondaryScreenshotBinding,
            keyCode: keyCode,
            eventFlags: eventFlags,
            triggerDown: &secondaryScreenshotTriggerDown,
            lastTapAt: &lastSecondaryScreenshotTapAt,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }
        if handleScreenshotFlagsChanged(
            binding: screenshotTranslationBinding,
            keyCode: keyCode,
            eventFlags: eventFlags,
            triggerDown: &screenshotTranslationTriggerDown,
            lastTapAt: &lastScreenshotTranslationTapAt,
            action: { [weak self] in self?.onScreenshotTranslation?() }
        ) {
            return true
        }
        if handleActionFlagsChanged(
            binding: autoTranslateBinding,
            keyCode: keyCode,
            eventFlags: eventFlags,
            triggerDown: &autoTranslateTriggerDown,
            actionKey: "autoTranslate",
            action: { [weak self] in self?.onAutoTranslateToggle?() }
        ) {
            return true
        }
        if handleActionFlagsChanged(
            binding: mainWindowBinding,
            keyCode: keyCode,
            eventFlags: eventFlags,
            triggerDown: &mainWindowTriggerDown,
            actionKey: "mainWindow",
            action: { [weak self] in self?.onMainWindow?() }
        ) {
            return true
        }
        if triggerDown, let activeChannel, let activePurpose, let activeBinding {
            if !isBindingDown(activeBinding, keyCode: keyCode, eventFlags: eventFlags) {
                return updateTrigger(
                    isDown: false,
                    channel: activeChannel,
                    purpose: activePurpose,
                    binding: activeBinding,
                    eventTimestamp: event.timestamp
                )
            }
            return true
        }

        if let target = bindings.first(where: { isBindingDown($0.binding, keyCode: keyCode, eventFlags: eventFlags) }) {
            return updateTrigger(
                isDown: true,
                channel: target.channel,
                purpose: target.purpose,
                binding: target.binding,
                eventTimestamp: event.timestamp
            )
        }

        if !bindings.contains(where: { requiredModifiersAreActive(for: $0.binding, eventFlags: eventFlags) }) {
            triggerDown = false
            activeChannel = nil
            activePurpose = nil
            activeBinding = nil
        }
        return false
    }

    func handleKey(event: CGEvent, isDown: Bool) -> Bool {
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let eventObservedAt = DispatchTime.now().uptimeNanoseconds
        let mappedRemoteDecision = RemoteMappedEventSuppressionRegistry.shared.decide(
            identity: .keyboard(keyCode: UInt16(eventKeyCode)),
            isDown: isDown,
            eventTimestamp: event.timestamp,
            observedAt: eventObservedAt,
            eventUserData: event.getIntegerValueField(.eventSourceUserData),
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        if mappedRemoteDecision.shouldConsume {
            LaunchDiagnostics.mark(
                "remote_mapped_event decision=consume kind=keyboard key_code=\(eventKeyCode) phase=\(isDown ? "down" : "up")"
            )
            return true
        }
        let remoteVoiceDecision = RemoteVoiceKeySuppressionRegistry.shared.decide(
            keyCode: eventKeyCode,
            isDown: isDown,
            eventTimestamp: event.timestamp,
            observedAt: eventObservedAt
        )
        if remoteVoiceDecision.shouldConsume {
            let phase = isDown ? "down" : "up"
            LaunchDiagnostics.mark(
                "remote_voice_f5 decision=\(remoteVoiceDecision.logName) phase=\(phase) event_uptime_ns=\(event.timestamp) observed_uptime_ns=\(eventObservedAt)"
            )
            return true
        }
        if AutoSendManualSubmitGate.shouldCancelCountdown(
            keyCode: eventKeyCode,
            isDown: isDown,
            eventUserData: event.getIntegerValueField(.eventSourceUserData)
        ) {
            onManualSubmitKey?()
        }
        if escapeCancellationGate.handle(
            keyCode: eventKeyCode,
            isDown: isDown,
            cancel: { [weak self] in self?.onEscape?() ?? false }
        ) {
            return true
        }
        if handleActionKey(
            binding: autoTranslateBinding,
            eventKeyCode: eventKeyCode,
            eventFlags: event.flags,
            isDown: isDown,
            triggerDown: &autoTranslateTriggerDown,
            actionKey: "autoTranslate",
            action: { [weak self] in self?.onAutoTranslateToggle?() }
        ) {
            return true
        }
        if handleActionKey(
            binding: mainWindowBinding,
            eventKeyCode: eventKeyCode,
            eventFlags: event.flags,
            isDown: isDown,
            triggerDown: &mainWindowTriggerDown,
            actionKey: "mainWindow",
            action: { [weak self] in self?.onMainWindow?() }
        ) {
            return true
        }

        if handleScreenshotKey(
            binding: screenshotBinding,
            eventKeyCode: eventKeyCode,
            eventFlags: event.flags,
            isDown: isDown,
            triggerDown: &screenshotTriggerDown,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }

        if handleScreenshotKey(
            binding: secondaryScreenshotBinding,
            eventKeyCode: eventKeyCode,
            eventFlags: event.flags,
            isDown: isDown,
            triggerDown: &secondaryScreenshotTriggerDown,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }

        if handleScreenshotKey(
            binding: screenshotTranslationBinding,
            eventKeyCode: eventKeyCode,
            eventFlags: event.flags,
            isDown: isDown,
            triggerDown: &screenshotTranslationTriggerDown,
            action: { [weak self] in self?.onScreenshotTranslation?() }
        ) {
            return true
        }

        if !isDown,
           triggerDown,
           let activeChannel,
           let activePurpose,
           let activeBinding,
           activeBinding.kind == .combo,
           activeBinding.keyCode == eventKeyCode {
            return updateTrigger(
                isDown: false,
                channel: activeChannel,
                purpose: activePurpose,
                binding: activeBinding,
                eventTimestamp: event.timestamp
            )
        }

        guard let target = bindings.first(where: { target in
            target.binding.kind == .combo &&
            target.binding.keyCode == eventKeyCode &&
            requiredModifiersAreActive(for: target.binding, eventFlags: event.flags)
        }) else {
            return false
        }
        return updateTrigger(
            isDown: isDown,
            channel: target.channel,
            purpose: target.purpose,
            binding: target.binding,
            eventTimestamp: event.timestamp
        )
    }

    func handleMouse(event: CGEvent, isDown: Bool) -> Bool {
        let eventMouseButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let eventFlags = event.flags

        if handleActionMouse(
            binding: autoTranslateBinding,
            eventMouseButton: eventMouseButton,
            eventFlags: eventFlags,
            isDown: isDown,
            triggerDown: &autoTranslateTriggerDown,
            actionKey: "autoTranslate",
            action: { [weak self] in self?.onAutoTranslateToggle?() }
        ) {
            return true
        }
        if handleActionMouse(
            binding: mainWindowBinding,
            eventMouseButton: eventMouseButton,
            eventFlags: eventFlags,
            isDown: isDown,
            triggerDown: &mainWindowTriggerDown,
            actionKey: "mainWindow",
            action: { [weak self] in self?.onMainWindow?() }
        ) {
            return true
        }
        if handleScreenshotMouse(
            binding: screenshotBinding,
            eventMouseButton: eventMouseButton,
            eventFlags: eventFlags,
            isDown: isDown,
            triggerDown: &screenshotTriggerDown,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }
        if handleScreenshotMouse(
            binding: secondaryScreenshotBinding,
            eventMouseButton: eventMouseButton,
            eventFlags: eventFlags,
            isDown: isDown,
            triggerDown: &secondaryScreenshotTriggerDown,
            action: { [weak self] in self?.onScreenshot?() }
        ) {
            return true
        }
        if handleScreenshotMouse(
            binding: screenshotTranslationBinding,
            eventMouseButton: eventMouseButton,
            eventFlags: eventFlags,
            isDown: isDown,
            triggerDown: &screenshotTranslationTriggerDown,
            action: { [weak self] in self?.onScreenshotTranslation?() }
        ) {
            return true
        }

        guard let target = bindings.first(where: { target in
            target.binding.kind == .mouse &&
            isMouseShortcutMatch(target.binding.keyCode, eventMouseButton: eventMouseButton) &&
            requiredModifiersAreActive(for: target.binding, eventFlags: eventFlags)
        }) else {
            return false
        }

        return updateTrigger(
            isDown: isDown,
            channel: target.channel,
            purpose: target.purpose,
            binding: target.binding,
            eventTimestamp: event.timestamp
        )
    }

    private func isMouseShortcutMatch(_ bindingMouseButton: Int?, eventMouseButton: Int) -> Bool {
        guard let bindingMouseButton else { return false }
        return bindingMouseButton == mappedMouseShortcutTag(for: eventMouseButton)
    }

    private func mappedMouseShortcutTag(for eventMouseButton: Int) -> Int {
        switch eventMouseButton {
        case 2:
            return 3
        case 3:
            return 4
        case 4:
            return 5
        case 5, 6, 7, 8:
            return 6
        default:
            return eventMouseButton
        }
    }

    private func shouldPassThroughMouseShortcutMouseEvent(_ eventMouseButton: Int) -> Bool {
        let mappedButton = mappedMouseShortcutTag(for: eventMouseButton)
        return (3...6).contains(mappedButton)
    }

    func handleSystemDefined(event: CGEvent) -> Bool {
        if let descriptor = systemDefinedEventDescriptor(from: event) {
            let decision = RemoteMappedEventSuppressionRegistry.shared.decide(
                identity: .systemDefined(keyType: descriptor.keyType),
                isDown: descriptor.isDown,
                eventTimestamp: event.timestamp,
                observedAt: DispatchTime.now().uptimeNanoseconds,
                eventUserData: event.getIntegerValueField(.eventSourceUserData),
                isAutoRepeat: false
            )
            if decision.shouldConsume {
                LaunchDiagnostics.mark(
                    "remote_mapped_event decision=consume kind=system_defined key_type=\(descriptor.keyType) phase=\(descriptor.isDown ? "down" : "up")"
                )
                return true
            }
        }
        guard !SyntheticMediaKeyEvent.isTypeWhaleGenerated(event) else { return false }
        guard let isDown = mediaPlayEvent(from: event) else { return false }
        if handleActionMedia(
            binding: autoTranslateBinding,
            isDown: isDown,
            triggerDown: &autoTranslateTriggerDown,
            actionKey: "autoTranslate",
            action: { [weak self] in self?.onAutoTranslateToggle?() }
        ) {
            return true
        }
        if handleActionMedia(
            binding: mainWindowBinding,
            isDown: isDown,
            triggerDown: &mainWindowTriggerDown,
            actionKey: "mainWindow",
            action: { [weak self] in self?.onMainWindow?() }
        ) {
            return true
        }
        if handleScreenshotMedia(binding: screenshotBinding, isDown: isDown, triggerDown: &screenshotTriggerDown, action: { [weak self] in self?.onScreenshot?() }) {
            return true
        }
        if handleScreenshotMedia(binding: secondaryScreenshotBinding, isDown: isDown, triggerDown: &secondaryScreenshotTriggerDown, action: { [weak self] in self?.onScreenshot?() }) {
            return true
        }
        if handleScreenshotMedia(binding: screenshotTranslationBinding, isDown: isDown, triggerDown: &screenshotTranslationTriggerDown, action: { [weak self] in self?.onScreenshotTranslation?() }) {
            return true
        }
        guard let target = bindings.first(where: { $0.binding.kind == .mediaPlay }) else {
            return false
        }
        return updateTrigger(
            isDown: isDown,
            channel: target.channel,
            purpose: target.purpose,
            binding: target.binding,
            eventTimestamp: event.timestamp
        )
    }

    private func handleScreenshotFlagsChanged(
        binding: HotkeyBinding?,
        keyCode: Int,
        eventFlags: CGEventFlags,
        triggerDown: inout Bool,
        lastTapAt: inout Date?,
        action: () -> Void
    ) -> Bool {
        guard let binding, binding.kind == .function || binding.kind == .modifier else { return false }
        guard !screenshotConflictsWithSpeechBinding(binding) else { return false }
        let isDown = isBindingDown(binding, keyCode: keyCode, eventFlags: eventFlags)
        guard isDown != triggerDown else { return false }
        triggerDown = isDown
        if !isDown {
            return registerScreenshotTap(lastTapAt: &lastTapAt, action: action)
        }
        return false
    }

    private func handleScreenshotMouse(
        binding: HotkeyBinding?,
        eventMouseButton: Int,
        eventFlags: CGEventFlags,
        isDown: Bool,
        triggerDown: inout Bool,
        action: () -> Void
    ) -> Bool {
        guard let binding, binding.kind == .mouse else { return false }
        guard isMouseShortcutMatch(binding.keyCode, eventMouseButton: eventMouseButton) else { return false }
        guard !screenshotConflictsWithSpeechBinding(binding) else { return false }
        guard requiredModifiersAreActive(for: binding, eventFlags: eventFlags) else { return false }
        guard isDown != triggerDown else { return false }
        triggerDown = isDown
        if isDown {
            action()
        }
        return true
    }

    private func handleScreenshotKey(
        binding: HotkeyBinding?,
        eventKeyCode: Int,
        eventFlags: CGEventFlags,
        isDown: Bool,
        triggerDown: inout Bool,
        action: () -> Void
    ) -> Bool {
        guard let binding,
              binding.kind == .combo,
              binding.keyCode == eventKeyCode else {
            return false
        }
        guard !screenshotConflictsWithSpeechBinding(binding) else { return false }
        if !isDown {
            guard triggerDown else { return false }
            triggerDown = false
            return true
        }
        guard requiredModifiersAreActive(for: binding, eventFlags: eventFlags) else {
            return false
        }
        // 修饰键+普通键的组合：单击即触发（区别于纯修饰键的双击）。
        if isDown != triggerDown {
            triggerDown = isDown
            action()
        }
        return true
    }

    private func handleScreenshotMedia(binding: HotkeyBinding?, isDown: Bool, triggerDown: inout Bool, action: () -> Void) -> Bool {
        guard let binding, binding.kind == .mediaPlay else { return false }
        guard !screenshotConflictsWithSpeechBinding(binding) else { return false }
        guard isDown != triggerDown else { return true }
        triggerDown = isDown
        if isDown {
            action()
        }
        return true
    }

    private func registerScreenshotTap(lastTapAt: inout Date?, action: () -> Void) -> Bool {
        let now = Date()
        guard let previousTapAt = lastTapAt,
              now.timeIntervalSince(previousTapAt) <= Timing.screenshotDoubleTapWindowSeconds else {
            lastTapAt = now
            return false
        }
        lastTapAt = nil
        action()
        return true
    }

    private func handleActionFlagsChanged(
        binding: HotkeyBinding?,
        keyCode: Int,
        eventFlags: CGEventFlags,
        triggerDown: inout Bool,
        actionKey: String,
        action: () -> Void
    ) -> Bool {
        guard let binding, binding.kind == .function || binding.kind == .modifier else { return false }
        let isDown = isBindingDown(binding, keyCode: keyCode, eventFlags: eventFlags)
        guard isDown != triggerDown else { return false }
        triggerDown = isDown
        if !isDown {
            triggerAction(binding: binding, actionKey: actionKey, action: action)
        }
        return true
    }

    private func handleActionMouse(
        binding: HotkeyBinding?,
        eventMouseButton: Int,
        eventFlags: CGEventFlags,
        isDown: Bool,
        triggerDown: inout Bool,
        actionKey: String,
        action: () -> Void
    ) -> Bool {
        guard let binding, binding.kind == .mouse else { return false }
        guard isMouseShortcutMatch(binding.keyCode, eventMouseButton: eventMouseButton) else { return false }
        guard requiredModifiersAreActive(for: binding, eventFlags: eventFlags) else { return false }
        guard isDown != triggerDown else { return true }
        triggerDown = isDown
        if isDown {
            triggerAction(binding: binding, actionKey: actionKey, action: action)
        }
        return true
    }

    private func handleActionKey(
        binding: HotkeyBinding?,
        eventKeyCode: Int,
        eventFlags: CGEventFlags,
        isDown: Bool,
        triggerDown: inout Bool,
        actionKey: String,
        action: () -> Void
    ) -> Bool {
        guard let binding,
              binding.kind == .combo,
              binding.keyCode == eventKeyCode else {
            return false
        }
        if !isDown {
            guard triggerDown else { return false }
            triggerDown = false
            return true
        }
        guard requiredModifiersAreActive(for: binding, eventFlags: eventFlags) else {
            return false
        }
        if isDown != triggerDown {
            triggerDown = isDown
            triggerAction(binding: binding, actionKey: actionKey, action: action)
        }
        return true
    }

    private func handleActionMedia(
        binding: HotkeyBinding?,
        isDown: Bool,
        triggerDown: inout Bool,
        actionKey: String,
        action: () -> Void
    ) -> Bool {
        guard let binding, binding.kind == .mediaPlay else { return false }
        guard isDown != triggerDown else { return true }
        triggerDown = isDown
        if isDown {
            triggerAction(binding: binding, actionKey: actionKey, action: action)
        }
        return true
    }

    private func triggerAction(binding: HotkeyBinding, actionKey: String, action: () -> Void) {
        let requiredTapCount = max(binding.tapCount ?? 1, 1)
        guard requiredTapCount > 1 else {
            action()
            return
        }
        let now = Date()
        let state = actionTapState[actionKey]
        let nextCount: Int
        if let state, now.timeIntervalSince(state.lastAt) <= Timing.actionTapWindowSeconds {
            nextCount = state.count + 1
        } else {
            nextCount = 1
        }
        if nextCount >= requiredTapCount {
            actionTapState[actionKey] = nil
            action()
        } else {
            actionTapState[actionKey] = (nextCount, now)
        }
    }

    private func screenshotConflictsWithSpeechBinding(_ binding: HotkeyBinding) -> Bool {
        bindings.contains { $0.binding == binding }
    }

    private func isBindingDown(_ binding: HotkeyBinding, keyCode: Int, eventFlags: CGEventFlags) -> Bool {
        switch binding.kind {
        case .function:
            return eventFlags.contains(.maskSecondaryFn) || activeModifierKeyCodes.contains(HotkeyKeyCodes.function)
        case .modifier:
            guard binding.keyCode == keyCode else { return false }
            let requiredFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
            return activeModifierKeyCodes.contains(keyCode) || (!requiredFlag.isEmpty && eventFlags.contains(requiredFlag))
        case .combo:
            return triggerDown && activeBinding == binding && requiredModifiersAreActive(for: binding, eventFlags: eventFlags)
        case .mediaPlay:
            return triggerDown && activeBinding == binding
        case .mouse:
            return activeBinding == binding && requiredModifiersAreActive(for: binding, eventFlags: eventFlags)
        }
    }

    private func requiredModifiersAreActive(for binding: HotkeyBinding, eventFlags: CGEventFlags) -> Bool {
        binding.modifierKeyCodes.allSatisfy { keyCode in
            if activeModifierKeyCodes.contains(keyCode) {
                return true
            }
            let requiredFlag = HotkeyKeyCodes.cgModifierFlags(for: keyCode)
            return !requiredFlag.isEmpty && eventFlags.contains(requiredFlag)
        }
    }

    private func updateTrigger(
        isDown: Bool,
        channel: SpeechInputChannel,
        purpose: SpeechInputPurpose,
        binding: HotkeyBinding,
        eventTimestamp: UInt64
    ) -> Bool {
        guard isDown != triggerDown else { return true }
        triggerDown = isDown
        let timing = HotkeyEventTiming(
            eventUptimeNanoseconds: eventTimestamp,
            observedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        let deliveryLag = timing.deliveryLagMilliseconds.map(String.init) ?? "unknown"
        if isDown {
            activeChannel = channel
            activePurpose = purpose
            activeBinding = binding
            LaunchDiagnostics.mark(
                "hotkey_event phase=down purpose=\(purpose.logName) binding=\(binding.displayName) event_uptime_ns=\(timing.eventUptimeNanoseconds) observed_uptime_ns=\(timing.observedUptimeNanoseconds) delivery_lag_ms=\(deliveryLag)"
            )
            onTimedDown?(channel, purpose, binding, timing)
            onDown?(channel, purpose, binding)
        } else {
            let channelToEnd = activeChannel ?? channel
            let purposeToEnd = activePurpose ?? purpose
            let bindingToEnd = activeBinding ?? binding
            activeChannel = nil
            activePurpose = nil
            activeBinding = nil
            LaunchDiagnostics.mark(
                "hotkey_event phase=up purpose=\(purposeToEnd.logName) binding=\(bindingToEnd.displayName) event_uptime_ns=\(timing.eventUptimeNanoseconds) observed_uptime_ns=\(timing.observedUptimeNanoseconds) delivery_lag_ms=\(deliveryLag)"
            )
            onTimedUp?(channelToEnd, purposeToEnd, bindingToEnd, timing)
            onUp?(channelToEnd, purposeToEnd, bindingToEnd)
        }
        return true
    }

    private func mediaPlayEvent(from event: CGEvent) -> Bool? {
        guard let descriptor = systemDefinedEventDescriptor(from: event),
              descriptor.keyType == MediaKey.play else { return nil }
        return descriptor.isDown
    }

    private func systemDefinedEventDescriptor(
        from event: CGEvent
    ) -> (keyType: Int32, isDown: Bool)? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == MediaKey.auxControlButtonSubtype else {
            return nil
        }
        let data = nsEvent.data1
        let keyType = Int32((data & 0xFFFF0000) >> 16)
        let keyState = (data & 0x0000FF00) >> 8
        switch keyState {
        case MediaKey.keyDownState:
            return (keyType, true)
        case 0x0B:
            return (keyType, false)
        default:
            return nil
        }
    }
}
