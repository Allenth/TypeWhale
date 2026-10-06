import Foundation

@main
struct RemoteHIDEventReducerCheck {
    static func main() {
        mapsKnownRC003Usages()
        pairsDownAndUpAndIgnoresRepeats()
        releasesThePreviousButtonWhenHardwareSwitchesWithoutKeyUp()
        clearReleasesAHeldButton()
        print("RemoteHIDEventReducerCheck passed")
    }

    private static func mapsKnownRC003Usages() {
        let map = XiaomiRemote2ProHIDProfile.buttons
        precondition(map.count == RemoteButton.allCases.count)
        precondition(Set(map.values) == Set(RemoteButton.allCases))
        precondition(XiaomiRemote2ProHIDProfile.supportedButtons == Set(RemoteButton.allCases))
        precondition(map[RemoteHIDUsage(page: 7, usage: 82)] == .dpadUp)
        precondition(map[RemoteHIDUsage(page: 7, usage: 40)] == .center)
        precondition(map[RemoteHIDUsage(page: 7, usage: 62)] == .voice)
        precondition(map[RemoteHIDUsage(page: 7, usage: 128)] == .volumeUp)
        precondition(map[RemoteHIDUsage(page: 7, usage: 129)] == .volumeDown)
        precondition(map[RemoteHIDUsage(page: 7, usage: 0x65)] == .menu)
    }

    private static func pairsDownAndUpAndIgnoresRepeats() {
        var reducer = RemoteHIDEventReducer()
        let map = XiaomiRemote2ProHIDProfile.buttons
        precondition(reducer.reduce(page: 7, usage: 40, value: 1, buttons: map) == [.buttonDown(.center)])
        precondition(reducer.reduce(page: 7, usage: 40, value: 2, buttons: map).isEmpty)
        precondition(reducer.reduce(page: 7, usage: 40, value: 0, buttons: map) == [.buttonUp(.center)])
        precondition(reducer.reduce(page: 7, usage: 40, value: 0, buttons: map).isEmpty)
        precondition(reducer.reduce(page: 7, usage: 999, value: 1, buttons: map).isEmpty)
    }

    private static func releasesThePreviousButtonWhenHardwareSwitchesWithoutKeyUp() {
        var reducer = RemoteHIDEventReducer()
        let map = XiaomiRemote2ProHIDProfile.buttons
        _ = reducer.reduce(page: 7, usage: 40, value: 1, buttons: map)
        precondition(reducer.reduce(page: 7, usage: 74, value: 1, buttons: map) == [
            .buttonUp(.center),
            .buttonDown(.home),
        ])
    }

    private static func clearReleasesAHeldButton() {
        var reducer = RemoteHIDEventReducer()
        _ = reducer.reduce(page: 7, usage: 241, value: 1, buttons: XiaomiRemote2ProHIDProfile.buttons)
        precondition(reducer.clear() == [.buttonUp(.back)])
        precondition(reducer.clear().isEmpty)
    }
}
