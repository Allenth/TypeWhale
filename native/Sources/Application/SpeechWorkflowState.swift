import Foundation

struct SpeechWorkflowState: Equatable {
    enum Phase: Equatable {
        case idle
        case recording(UUID)
        case finalizing(UUID)
        case pasting(UUID)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var latestSubmittedTaskID: UUID?
    private(set) var submittedTaskIDs: [UUID] = []
    private(set) var completedFinalTaskIDs: [UUID] = []
    var completedFinalTaskLimit = 20

    mutating func startRecording(taskID: UUID) {
        phase = .recording(taskID)
    }

    mutating func submitFinalTask(_ taskID: UUID) {
        phase = .finalizing(taskID)
        latestSubmittedTaskID = taskID
        if !submittedTaskIDs.contains(taskID) {
            submittedTaskIDs.append(taskID)
        }
    }

    mutating func startPasting(taskID: UUID) {
        phase = .pasting(taskID)
    }

    mutating func finishTask(_ taskID: UUID) {
        submittedTaskIDs.removeAll { $0 == taskID }
        if phase.taskID == taskID {
            phase = .idle
        }
        if latestSubmittedTaskID == taskID {
            latestSubmittedTaskID = submittedTaskIDs.last
        }
    }

    mutating func cancelActiveTask() {
        phase = .idle
        latestSubmittedTaskID = nil
        submittedTaskIDs.removeAll()
    }

    mutating func fail(_ message: String) {
        phase = .failed(message)
    }

    func shouldUpdateInterface(for taskID: UUID, isRecording: Bool) -> Bool {
        latestSubmittedTaskID == taskID && !isRecording
    }

    func canHidePopup(for taskID: UUID, isRecording: Bool) -> Bool {
        !isRecording && (latestSubmittedTaskID == nil || latestSubmittedTaskID == taskID)
    }

    func canSubmitProcessedResult(taskID: UUID) -> Bool {
        submittedTaskIDs.contains(taskID)
    }

    func canAcceptRealtimeCallback(taskID: UUID, activeSessionID: UUID?) -> Bool {
        activeSessionID == taskID && phase == .recording(taskID)
    }

    mutating func markFinalTaskForSubmission(_ taskID: UUID) -> Bool {
        if completedFinalTaskIDs.contains(taskID) {
            return false
        }
        completedFinalTaskIDs.append(taskID)
        while completedFinalTaskIDs.count > completedFinalTaskLimit {
            completedFinalTaskIDs.removeFirst()
        }
        return true
    }
}

private extension SpeechWorkflowState.Phase {
    var taskID: UUID? {
        switch self {
        case .idle, .failed:
            return nil
        case .recording(let id), .finalizing(let id), .pasting(let id):
            return id
        }
    }
}
