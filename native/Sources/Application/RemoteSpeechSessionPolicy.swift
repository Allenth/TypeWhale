import Foundation

struct RemoteSpeechSessionPolicy {
    private(set) var activeTaskID: UUID?

    mutating func accept(taskID: UUID) -> Bool {
        guard activeTaskID == nil else { return false }
        activeTaskID = taskID
        return true
    }

    func allowsPCM(taskID: UUID) -> Bool {
        activeTaskID == taskID
    }

    mutating func finish(taskID: UUID) -> Bool {
        guard activeTaskID == taskID else { return false }
        activeTaskID = nil
        return true
    }

    mutating func cancel() -> UUID? {
        defer { activeTaskID = nil }
        return activeTaskID
    }
}
