import ApplicationServices
import Foundation

@main
enum RemoteKeyboardActionEmitterCheck {
    static func main() {
        var batches: [[RemoteSyntheticKeyEventSpec]] = []
        let emitter = RemoteKeyboardActionEmitter { events in
            batches.append(events)
            return events.first?.keyCode != 51
        }

        precondition(emitter.emit(.keyboardEscape))
        precondition(!emitter.emit(.keyboardDelete))
        precondition(emitter.emit(.keyboardReturn))
        precondition(emitter.emit(.lockMac))
        precondition(!emitter.emit(.send))

        precondition(batches.count == 4)
        assertPair(batches[0], keyCode: 53, flags: [])
        assertPair(batches[1], keyCode: 51, flags: [])
        assertPair(batches[2], keyCode: 36, flags: [])
        assertPair(batches[3], keyCode: 12, flags: [.maskControl, .maskCommand])
        print("RemoteKeyboardActionEmitterCheck passed")
    }

    private static func assertPair(
        _ events: [RemoteSyntheticKeyEventSpec],
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) {
        precondition(events.count == 2)
        precondition(events[0].keyCode == keyCode)
        precondition(events[0].flags == flags)
        precondition(events[0].isDown)
        precondition(events[0].userData == RemoteSyntheticKeyEventSpec.userData)
        precondition(events[1].keyCode == keyCode)
        precondition(events[1].flags == flags)
        precondition(!events[1].isDown)
        precondition(events[1].userData == RemoteSyntheticKeyEventSpec.userData)
    }
}
