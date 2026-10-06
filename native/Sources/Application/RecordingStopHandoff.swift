import Foundation

/// Owns the short handoff between accepting a stop request and releasing the
/// recording-specific preview/audio resources. Final recognition is tracked by
/// `SpeechWorkflowState` after this handoff completes.
struct RecordingStopHandoff: Equatable {
    private(set) var taskID: UUID?

    mutating func begin(taskID: UUID) -> Bool {
        guard self.taskID == nil else { return false }
        self.taskID = taskID
        return true
    }

    func owns(taskID: UUID) -> Bool {
        self.taskID == taskID
    }

    mutating func complete(taskID: UUID) -> Bool {
        guard self.taskID == taskID else { return false }
        self.taskID = nil
        return true
    }

    mutating func cancel(taskID: UUID) -> Bool {
        complete(taskID: taskID)
    }

    mutating func reset() {
        taskID = nil
    }
}
