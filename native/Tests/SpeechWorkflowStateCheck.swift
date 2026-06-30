import Foundation

@main
struct SpeechWorkflowStateCheck {
    static func main() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var state = SpeechWorkflowState()

        state.startRecording(taskID: first)
        precondition(state.phase == .recording(first))
        precondition(!state.shouldUpdateInterface(for: first, isRecording: true))
        precondition(state.canAcceptRealtimeCallback(taskID: first, activeSessionID: first))
        precondition(!state.canAcceptRealtimeCallback(taskID: second, activeSessionID: first))

        state.submitFinalTask(first)
        precondition(state.phase == .finalizing(first))
        precondition(state.shouldUpdateInterface(for: first, isRecording: false))
        precondition(state.canSubmitProcessedResult(taskID: first))
        precondition(!state.shouldUpdateInterface(for: second, isRecording: false))
        precondition(!state.canSubmitProcessedResult(taskID: second))
        precondition(!state.canAcceptRealtimeCallback(taskID: first, activeSessionID: first))

        precondition(state.markFinalTaskForSubmission(first))
        precondition(!state.markFinalTaskForSubmission(first))

        state.startRecording(taskID: second)
        precondition(state.phase == .recording(second))
        precondition(!state.shouldUpdateInterface(for: first, isRecording: false))
        precondition(!state.canSubmitProcessedResult(taskID: first))
        precondition(state.canAcceptRealtimeCallback(taskID: second, activeSessionID: second))

        state.submitFinalTask(second)
        state.startPasting(taskID: second)
        precondition(state.phase == .pasting(second))
        state.finishTask(first)
        precondition(state.phase == .pasting(second))
        state.finishTask(second)
        precondition(state.phase == .idle)

        state.completedFinalTaskLimit = 2
        precondition(state.markFinalTaskForSubmission(second))
        precondition(state.markFinalTaskForSubmission(third))
        let fourth = UUID()
        precondition(state.markFinalTaskForSubmission(fourth))
        precondition(state.completedFinalTaskIDs == [third, fourth])

        state.cancelActiveTask()
        precondition(state.phase == .idle)
        precondition(!state.shouldUpdateInterface(for: second, isRecording: false))
    }
}
