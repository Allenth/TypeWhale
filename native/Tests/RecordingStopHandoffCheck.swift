import Foundation

@main
struct RecordingStopHandoffCheck {
    static func main() {
        acceptsOneStopOwnerAndRejectsDuplicates()
        rejectsStaleCompletionWithoutReleasingOwner()
        releasesTheOwnerForTheNextRecording()
        cancellationIsScopedToTheOwnedTask()
        print("RecordingStopHandoffCheck passed")
    }

    private static func acceptsOneStopOwnerAndRejectsDuplicates() {
        let taskID = UUID()
        var handoff = RecordingStopHandoff()

        precondition(handoff.begin(taskID: taskID))
        precondition(handoff.owns(taskID: taskID))
        precondition(!handoff.begin(taskID: taskID), "duplicate stop must be idempotently rejected")
        precondition(!handoff.begin(taskID: UUID()), "a second task cannot replace the active stop owner")
    }

    private static func rejectsStaleCompletionWithoutReleasingOwner() {
        let taskID = UUID()
        var handoff = RecordingStopHandoff()
        precondition(handoff.begin(taskID: taskID))

        precondition(!handoff.complete(taskID: UUID()))
        precondition(handoff.owns(taskID: taskID), "stale completion must not release the real owner")
    }

    private static func releasesTheOwnerForTheNextRecording() {
        let first = UUID()
        let second = UUID()
        var handoff = RecordingStopHandoff()
        precondition(handoff.begin(taskID: first))
        precondition(handoff.complete(taskID: first))
        precondition(!handoff.owns(taskID: first))
        precondition(handoff.begin(taskID: second), "a completed audio handoff must not block the next session")
    }

    private static func cancellationIsScopedToTheOwnedTask() {
        let taskID = UUID()
        var handoff = RecordingStopHandoff()
        precondition(handoff.begin(taskID: taskID))

        precondition(!handoff.cancel(taskID: UUID()))
        precondition(handoff.owns(taskID: taskID))
        precondition(handoff.cancel(taskID: taskID))
        precondition(!handoff.owns(taskID: taskID))
    }
}
