import Foundation

@main
struct RemoteSpeechSessionPolicyCheck {
    static func main() {
        ownsExactlyOneAcceptedRemoteSession()
        rejectsStalePCMAndStopEvents()
        cancelClearsOwnership()
        print("RemoteSpeechSessionPolicyCheck passed")
    }

    private static func ownsExactlyOneAcceptedRemoteSession() {
        var policy = RemoteSpeechSessionPolicy()
        let first = UUID()
        let second = UUID()
        precondition(policy.accept(taskID: first))
        precondition(!policy.accept(taskID: second))
        precondition(policy.allowsPCM(taskID: first))
        precondition(!policy.allowsPCM(taskID: second))
    }

    private static func rejectsStalePCMAndStopEvents() {
        var policy = RemoteSpeechSessionPolicy()
        let active = UUID()
        let stale = UUID()
        precondition(policy.accept(taskID: active))
        precondition(!policy.finish(taskID: stale))
        precondition(policy.allowsPCM(taskID: active))
        precondition(policy.finish(taskID: active))
        precondition(!policy.allowsPCM(taskID: active))
        precondition(!policy.finish(taskID: active))
    }

    private static func cancelClearsOwnership() {
        var policy = RemoteSpeechSessionPolicy()
        let taskID = UUID()
        precondition(policy.accept(taskID: taskID))
        precondition(policy.cancel() == taskID)
        precondition(policy.cancel() == nil)
        precondition(policy.activeTaskID == nil)
    }
}
