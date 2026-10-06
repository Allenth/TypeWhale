import ApplicationServices
import Foundation

protocol PostPasteKeyEmitting {
    func emit(_ action: PostPasteAction) -> Bool
}

struct SystemPostPasteKeyEmitter: PostPasteKeyEmitting {
    typealias PostKey = (CGKeyCode, CGEventFlags) -> Bool

    private let postKey: PostKey

    init(postKey: @escaping PostKey = Self.postSystemKey) {
        self.postKey = postKey
    }

    func emit(_ action: PostPasteAction) -> Bool {
        switch action {
        case .none:
            return true
        case .returnKey:
            return postKey(36, [])
        case .commandReturn:
            return postKey(36, .maskCommand)
        }
    }

    private static func postSystemKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let up = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              ) else {
            return false
        }
        source.localEventsSuppressionInterval = 0
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(
            .eventSourceUserData,
            value: AutoSendManualSubmitGate.syntheticEventUserData
        )
        up.setIntegerValueField(
            .eventSourceUserData,
            value: AutoSendManualSubmitGate.syntheticEventUserData
        )
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
