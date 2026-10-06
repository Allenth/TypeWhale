import Foundation

struct RemoteHIDUsage: Hashable {
    let page: Int
    let usage: Int
}

enum RemoteHIDButtonEvent: Equatable {
    case buttonDown(RemoteButton)
    case buttonUp(RemoteButton)
}

struct RemoteHIDEventReducer {
    private var activeUsage: RemoteHIDUsage?
    private var activeButton: RemoteButton?

    mutating func reduce(
        page: Int,
        usage: Int,
        value: Int,
        buttons: [RemoteHIDUsage: RemoteButton]
    ) -> [RemoteHIDButtonEvent] {
        let key = RemoteHIDUsage(page: page, usage: usage)
        if value == 0 {
            guard key == activeUsage else { return [] }
            return clear()
        }
        guard let button = buttons[key], key != activeUsage else { return [] }
        var events = clear()
        activeUsage = key
        activeButton = button
        events.append(.buttonDown(button))
        return events
    }

    mutating func clear() -> [RemoteHIDButtonEvent] {
        defer {
            activeUsage = nil
            activeButton = nil
        }
        guard let activeButton else { return [] }
        return [.buttonUp(activeButton)]
    }
}
