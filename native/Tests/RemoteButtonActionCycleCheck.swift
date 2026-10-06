import Foundation

@main
enum RemoteButtonActionCycleCheck {
    static func main() {
        var tracker = RemoteButtonActionCycleTracker()
        var mapping = RemoteButtonMapping.defaults

        let started = tracker.begin(button: .voice, mapping: mapping)
        precondition(started.actionID == .pushToTalk)

        mapping.set(.keyboardEscape, for: .voice)
        precondition(tracker.begin(button: .voice, mapping: mapping) == started)
        precondition(tracker.binding(for: .voice, fallback: mapping) == started)
        precondition(tracker.end(button: .voice, fallback: mapping) == started)
        precondition(tracker.binding(for: .voice, fallback: mapping).actionID == .keyboardEscape)

        precondition(RemoteButtonAction.pushToTalk.startsRemoteSpeech)
        for action in RemoteButtonAction.allCases where action != .pushToTalk {
            precondition(!action.startsRemoteSpeech)
        }

        _ = tracker.begin(button: .back, mapping: mapping)
        tracker.reset()
        precondition(tracker.binding(for: .back, fallback: mapping).actionID == .systemPassThrough)
        print("RemoteButtonActionCycleCheck passed")
    }
}
