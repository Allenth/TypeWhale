import Foundation

enum XiaomiRemote2ProHIDProfile {
    static let vendorID = 0x2717
    static let productID = 0x32B8

    static let buttons: [RemoteHIDUsage: RemoteButton] = [
        RemoteHIDUsage(page: 7, usage: 0x66): .power,
        RemoteHIDUsage(page: 7, usage: 0x52): .dpadUp,
        RemoteHIDUsage(page: 7, usage: 0x50): .dpadLeft,
        RemoteHIDUsage(page: 7, usage: 0x28): .center,
        RemoteHIDUsage(page: 7, usage: 0x4F): .dpadRight,
        RemoteHIDUsage(page: 7, usage: 0x51): .dpadDown,
        RemoteHIDUsage(page: 7, usage: 0xF1): .back,
        RemoteHIDUsage(page: 7, usage: 0x80): .volumeUp,
        RemoteHIDUsage(page: 7, usage: 0x4A): .home,
        RemoteHIDUsage(page: 7, usage: 0x81): .volumeDown,
        RemoteHIDUsage(page: 7, usage: 0x65): .menu,
        RemoteHIDUsage(page: 7, usage: 0x35): .tv,
        RemoteHIDUsage(page: 7, usage: 0x3E): .voice,
    ]

    static let supportedButtons = Set(buttons.values)

    static func isVoiceUsage(page: Int, usage: Int) -> Bool {
        buttons[RemoteHIDUsage(page: page, usage: usage)] == .voice
    }
}
