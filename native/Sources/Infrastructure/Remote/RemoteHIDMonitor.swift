import ApplicationServices
import Darwin
import Foundation
import IOKit.hid

private func typeWhaleRemoteHIDValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard result == kIOReturnSuccess, let context else { return }
    let monitor = Unmanaged<RemoteHIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.receive(value: value)
}

private func typeWhaleRemoteHIDRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<RemoteHIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceWasRemoved()
}

final class RemoteHIDMonitor {
    var onEvent: ((RemoteHIDButtonEvent) -> Void)?
    var onPermissionChange: ((RemotePermissionStatus) -> Void)?
    var shouldSuppressSystemEvent: ((RemoteButton) -> Bool)?

    private var manager: IOHIDManager?
    private var reducer = RemoteHIDEventReducer()
    private var suppressionCycle: (
        usage: RemoteHIDUsage,
        button: RemoteButton,
        suppresses: Bool
    )?

    func start() {
        guard manager == nil else { return }
        RemoteVoiceKeySuppressionRegistry.shared.reset()
        RemoteMappedEventSuppressionRegistry.shared.reset()
        suppressionCycle = nil
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: XiaomiRemote2ProHIDProfile.vendorID,
            kIOHIDProductIDKey as String: XiaomiRemote2ProHIDProfile.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, typeWhaleRemoteHIDValueCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, typeWhaleRemoteHIDRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        onPermissionChange?(result == kIOReturnSuccess ? permissionStatus : .denied)
    }

    func stop() {
        RemoteVoiceKeySuppressionRegistry.shared.reset()
        RemoteMappedEventSuppressionRegistry.shared.reset()
        suppressionCycle = nil
        guard let manager else { return }
        for event in reducer.clear() { onEvent?(event) }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    var permissionStatus: RemotePermissionStatus {
        CGPreflightListenEventAccess() ? .allowed : .denied
    }

    fileprivate func receive(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let rawValue = IOHIDValueGetIntegerValue(value)
        let key = RemoteHIDUsage(page: page, usage: usage)
        let isDown = rawValue != 0
        let eventTimestamp = Self.nanoseconds(fromAbsoluteTime: IOHIDValueGetTimeStamp(value))
        let observedAt = DispatchTime.now().uptimeNanoseconds

        if isDown,
           suppressionCycle?.usage != key,
           let previous = suppressionCycle {
            if previous.suppresses {
                observeSuppression(
                    button: previous.button,
                    isDown: false,
                    eventTimestamp: eventTimestamp,
                    observedAt: observedAt
                )
            }
            suppressionCycle = nil
        }
        if isDown,
           suppressionCycle == nil,
           let button = XiaomiRemote2ProHIDProfile.buttons[key] {
            suppressionCycle = (
                usage: key,
                button: button,
                suppresses: shouldSuppressSystemEvent?(button) ?? false
            )
        }
        if let cycle = suppressionCycle,
           cycle.usage == key,
           cycle.suppresses {
            observeSuppression(
                button: cycle.button,
                isDown: isDown,
                eventTimestamp: eventTimestamp,
                observedAt: observedAt
            )
        }

        if XiaomiRemote2ProHIDProfile.isVoiceUsage(page: page, usage: usage),
           suppressionCycle?.usage == key,
           suppressionCycle?.suppresses == true {
            RemoteVoiceKeySuppressionRegistry.shared.observeRemoteVoiceHID(
                isDown: isDown,
                eventTimestamp: eventTimestamp,
                observedAt: observedAt
            )
            let phase = isDown ? "down" : "up"
            LaunchDiagnostics.mark(
                "remote_voice_hid phase=\(phase) usage=\(usage) event_uptime_ns=\(eventTimestamp) observed_uptime_ns=\(observedAt)"
            )
        }
        let events = reducer.reduce(
            page: page,
            usage: usage,
            value: rawValue,
            buttons: XiaomiRemote2ProHIDProfile.buttons
        )
        for event in events { onEvent?(event) }
        if !isDown, suppressionCycle?.usage == key {
            suppressionCycle = nil
        }
    }

    fileprivate func deviceWasRemoved() {
        RemoteVoiceKeySuppressionRegistry.shared.reset()
        RemoteMappedEventSuppressionRegistry.shared.reset()
        suppressionCycle = nil
        for event in reducer.clear() { onEvent?(event) }
    }

    private func observeSuppression(
        button: RemoteButton,
        isDown: Bool,
        eventTimestamp: UInt64,
        observedAt: UInt64
    ) {
        guard button != .voice else { return }
        RemoteMappedEventSuppressionRegistry.shared.observeRemoteHID(
            button: button,
            isDown: isDown,
            eventTimestamp: eventTimestamp,
            observedAt: observedAt
        )
    }

    private static let machTimebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }()

    private static func nanoseconds(fromAbsoluteTime value: UInt64) -> UInt64 {
        let numerator = UInt64(machTimebase.numer)
        let denominator = UInt64(max(1, machTimebase.denom))
        let whole = value / denominator
        let remainder = value % denominator
        return whole * numerator + remainder * numerator / denominator
    }
}
