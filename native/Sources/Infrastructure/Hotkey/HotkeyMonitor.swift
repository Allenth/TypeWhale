import ApplicationServices
import Foundation

final class HotkeyMonitor {
    private enum Timing {
        static let screenshotDoubleTapWindowSeconds: TimeInterval = 0.42
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var bindings = [
        HotkeyBinding.load(storageKey: HotkeyBinding.chineseStorageKey, fallback: .defaultBinding),
    ]
    private var screenshotBinding = HotkeyBinding.load(
        storageKey: HotkeyBinding.screenshotStorageKey,
        fallback: .screenshotDefaultBinding
    )
    private var activeModifierKeyCodes: Set<Int> = []
    private var triggerDown = false
    private var screenshotTriggerDown = false
    private var lastScreenshotTapAt: Date?
    private var activeChannel: SpeechInputChannel?
    private var activeBinding: HotkeyBinding?
    var onDown: ((SpeechInputChannel, HotkeyBinding) -> Void)?
    var onUp: ((SpeechInputChannel, HotkeyBinding) -> Void)?
    var onAutoTranslateToggle: (() -> Void)?
    var onScreenshot: (() -> Void)?

    func start() {
        guard tap == nil || !isTapEnabled else { return }
        stopEventTap()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
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
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    var isGlobalListening: Bool {
        isTapEnabled
    }

    private var isTapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func update(_ binding: HotkeyBinding) {
        update(primary: binding, secondary: nil)
    }

    func update(primary: HotkeyBinding, secondary: HotkeyBinding?) {
        update(primary: primary, secondary: secondary, screenshot: screenshotBinding)
    }

    func update(primary: HotkeyBinding, secondary: HotkeyBinding?, screenshot: HotkeyBinding) {
        self.bindings = [primary] + (secondary.map { [$0] } ?? [])
        self.screenshotBinding = screenshot
        activeModifierKeyCodes.removeAll()
        triggerDown = false
        screenshotTriggerDown = false
        lastScreenshotTapAt = nil
        activeChannel = nil
        activeBinding = nil
    }

    private func reenableEventTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil
        tap = nil
    }

    private func handleFlagsChanged(event: CGEvent) -> Bool {
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
        if handleScreenshotFlagsChanged(keyCode: keyCode, eventFlags: eventFlags) {
            return true
        }
        if triggerDown, let activeChannel, let activeBinding {
            if !isBindingDown(activeBinding, keyCode: keyCode, eventFlags: eventFlags) {
                return updateTrigger(isDown: false, channel: activeChannel, binding: activeBinding)
            }
            return true
        }

        if let binding = bindings.first(where: { isBindingDown($0, keyCode: keyCode, eventFlags: eventFlags) }) {
            return updateTrigger(isDown: true, channel: .chinese, binding: binding)
        }

        if !bindings.contains(where: { requiredModifiersAreActive(for: $0, eventFlags: eventFlags) }) {
            triggerDown = false
            activeChannel = nil
            activeBinding = nil
        }
        return false
    }

    private func handleKey(event: CGEvent, isDown: Bool) -> Bool {
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if isAutoTranslateToggle(eventKeyCode: eventKeyCode, eventFlags: event.flags) {
            if isDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onAutoTranslateToggle?()
            }
            return true
        }

        if handleScreenshotKey(eventKeyCode: eventKeyCode, eventFlags: event.flags, isDown: isDown) {
            return true
        }

        guard let binding = bindings.first(where: { binding in
            binding.kind == .combo &&
            binding.keyCode == eventKeyCode &&
            requiredModifiersAreActive(for: binding, eventFlags: event.flags)
        }) else {
            return false
        }
        return updateTrigger(isDown: isDown, channel: .chinese, binding: binding)
    }

    private func handleScreenshotFlagsChanged(keyCode: Int, eventFlags: CGEventFlags) -> Bool {
        guard screenshotBinding.kind == .function || screenshotBinding.kind == .modifier else { return false }
        let isDown = isBindingDown(screenshotBinding, keyCode: keyCode, eventFlags: eventFlags)
        guard isDown != screenshotTriggerDown else { return false }
        screenshotTriggerDown = isDown
        if !isDown {
            return registerScreenshotTap() || screenshotConflictsWithSpeechBinding
        }
        return screenshotConflictsWithSpeechBinding
    }

    private func handleScreenshotKey(eventKeyCode: Int, eventFlags: CGEventFlags, isDown: Bool) -> Bool {
        guard screenshotBinding.kind == .combo,
              screenshotBinding.keyCode == eventKeyCode,
              requiredModifiersAreActive(for: screenshotBinding, eventFlags: eventFlags) else {
            return false
        }
        guard isDown != screenshotTriggerDown else { return false }
        screenshotTriggerDown = isDown
        if !isDown {
            return registerScreenshotTap() || screenshotConflictsWithSpeechBinding
        }
        return screenshotConflictsWithSpeechBinding
    }

    private func registerScreenshotTap() -> Bool {
        let now = Date()
        guard let previousTapAt = lastScreenshotTapAt,
              now.timeIntervalSince(previousTapAt) <= Timing.screenshotDoubleTapWindowSeconds else {
            lastScreenshotTapAt = now
            return false
        }
        lastScreenshotTapAt = nil
        onScreenshot?()
        return true
    }

    private var screenshotConflictsWithSpeechBinding: Bool {
        bindings.contains(screenshotBinding)
    }

    private func isAutoTranslateToggle(eventKeyCode: Int, eventFlags: CGEventFlags) -> Bool {
        guard eventKeyCode == HotkeyKeyCodes.backslash else { return false }
        guard eventFlags.contains(.maskShift) else { return false }
        return !eventFlags.contains(.maskCommand) &&
            !eventFlags.contains(.maskAlternate) &&
            !eventFlags.contains(.maskControl) &&
            !eventFlags.contains(.maskSecondaryFn)
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

    private func updateTrigger(isDown: Bool, channel: SpeechInputChannel, binding: HotkeyBinding) -> Bool {
        guard isDown != triggerDown else { return true }
        triggerDown = isDown
        if isDown {
            activeChannel = channel
            activeBinding = binding
            onDown?(channel, binding)
        } else {
            let channelToEnd = activeChannel ?? channel
            let bindingToEnd = activeBinding ?? binding
            activeChannel = nil
            activeBinding = nil
            onUp?(channelToEnd, bindingToEnd)
        }
        return true
    }
}
