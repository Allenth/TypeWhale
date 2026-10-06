import ApplicationServices
import Foundation

struct RemoteSyntheticKeyEventSpec: Equatable {
    static let userData: Int64 = 0x5457_524D

    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let isDown: Bool
    let userData: Int64
}

struct RemoteKeyboardActionEmitter {
    typealias PostEvents = ([RemoteSyntheticKeyEventSpec]) -> Bool

    private let postEvents: PostEvents

    init(postEvents: @escaping PostEvents = Self.postSystemEvents) {
        self.postEvents = postEvents
    }

    func emit(_ action: RemoteButtonAction) -> Bool {
        guard let stroke = stroke(for: action) else { return false }
        return postEvents([
            RemoteSyntheticKeyEventSpec(
                keyCode: stroke.keyCode,
                flags: stroke.flags,
                isDown: true,
                userData: RemoteSyntheticKeyEventSpec.userData
            ),
            RemoteSyntheticKeyEventSpec(
                keyCode: stroke.keyCode,
                flags: stroke.flags,
                isDown: false,
                userData: RemoteSyntheticKeyEventSpec.userData
            ),
        ])
    }

    private func stroke(
        for action: RemoteButtonAction
    ) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        switch action {
        case .keyboardEscape:
            return (53, [])
        case .keyboardDelete:
            return (51, [])
        case .keyboardReturn:
            return (36, [])
        case .lockMac:
            return (12, [.maskControl, .maskCommand])
        case .pushToTalk, .send, .cancel, .toggleMainWindow, .none, .system:
            return nil
        }
    }

    private static func postSystemEvents(_ specs: [RemoteSyntheticKeyEventSpec]) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.localEventsSuppressionInterval = 0

        var events: [CGEvent] = []
        for spec in specs {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: spec.keyCode,
                keyDown: spec.isDown
            ) else { return false }
            event.flags = spec.flags
            event.setIntegerValueField(.eventSourceUserData, value: spec.userData)
            events.append(event)
        }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
