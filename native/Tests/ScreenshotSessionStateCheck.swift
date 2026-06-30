import Foundation

@main
struct ScreenshotSessionStateCheck {
    static func main() {
        let allCommands = ScreenshotToolbarCommand.allCases
        let outputCommands: [ScreenshotToolbarCommand] = [
            .copy, .save, .ocr, .translate, .annotate, .rectangle, .arrow, .pen, .text, .undo, .done
        ]

        let idle = ScreenshotSessionState(phase: .idle, hasSelection: false)
        precondition(idle.canPerform(.cancel))
        precondition(outputCommands.allSatisfy { !idle.canPerform($0) })
        precondition(idle.canHandlePointerInput)

        let idleWithSelection = ScreenshotSessionState(phase: .idle, hasSelection: true)
        precondition(allCommands.allSatisfy { idleWithSelection.canPerform($0) })
        let idleWithRealSelectionContext = ScreenshotCommandContext(
            sessionState: idle,
            hasUsableSelection: true
        )
        precondition(ScreenshotCommandDispatcher.canPerform(.copy, in: idleWithRealSelectionContext))
        precondition(ScreenshotCommandDispatcher.effect(for: .copy, in: idleWithRealSelectionContext) == .copy)

        let selectingWithSelection = ScreenshotSessionState(phase: .selecting, hasSelection: true)
        precondition(allCommands.allSatisfy { selectingWithSelection.canPerform($0) })
        precondition(selectingWithSelection.canAdjustSelection)

        let selected = ScreenshotSessionState(phase: .selected, hasSelection: true)
        precondition(allCommands.allSatisfy { selected.canPerform($0) })
        precondition(selected.canHandlePointerInput)
        precondition(selected.canAdjustSelection)
        let selectedContext = ScreenshotCommandContext(
            sessionState: selected,
            hasUsableSelection: true,
            operationGeneration: 2,
            isAnnotating: false,
            activeAnnotationTool: .rectangle
        )
        precondition(ScreenshotCommandDispatcher.effect(for: .copy, in: selectedContext) == .copy)
        precondition(ScreenshotCommandDispatcher.effect(for: .save, in: selectedContext) == .save)
        precondition(ScreenshotCommandDispatcher.effect(for: .ocr, in: selectedContext) == .ocr)
        precondition(ScreenshotCommandDispatcher.effect(for: .translate, in: selectedContext) == .translate)
        precondition(ScreenshotCommandDispatcher.effect(for: .annotate, in: selectedContext) == .startAnnotation(.rectangle))
        precondition(ScreenshotCommandDispatcher.effect(for: .pen, in: selectedContext) == .selectAnnotationTool(.pen))
        precondition(ScreenshotCommandDispatcher.effect(for: .done, in: selectedContext) == .done)
        precondition(ScreenshotCommandDispatcher.effect(for: .cancel, in: selectedContext) == .cancel)

        let selectedWithoutSelection = ScreenshotSessionState(phase: .selected, hasSelection: false)
        precondition(selectedWithoutSelection.canPerform(.cancel))
        precondition(outputCommands.allSatisfy { !selectedWithoutSelection.canPerform($0) })
        precondition(!selectedWithoutSelection.canAdjustSelection)

        for phase in [ScreenshotSessionState.Phase.translating, .windowRecapturePending] {
            let pending = ScreenshotSessionState(phase: phase, hasSelection: true)
            precondition(pending.canPerform(.cancel))
            precondition(outputCommands.allSatisfy { !pending.canPerform($0) })
            precondition(!pending.canHandlePointerInput)
            precondition(!pending.canAdjustSelection)
            let pendingContext = ScreenshotCommandContext(
                sessionState: pending,
                hasUsableSelection: true,
                operationGeneration: 3,
                isAnnotating: true,
                activeAnnotationTool: .text
            )
            precondition(ScreenshotCommandDispatcher.effect(for: .copy, in: pendingContext) == .ignore)
            precondition(ScreenshotCommandDispatcher.effect(for: .translate, in: pendingContext) == .ignore)
            precondition(ScreenshotCommandDispatcher.effect(for: .cancel, in: pendingContext) == .cancel)
        }

        for phase in [ScreenshotSessionState.Phase.completed, .cancelled] {
            let terminal = ScreenshotSessionState(phase: phase, hasSelection: true)
            precondition(allCommands.allSatisfy { !terminal.canPerform($0) })
            precondition(!terminal.canHandlePointerInput)
            let terminalContext = ScreenshotCommandContext(
                sessionState: terminal,
                hasUsableSelection: true
            )
            precondition(ScreenshotCommandDispatcher.effect(for: .cancel, in: terminalContext) == .ignore)
            precondition(ScreenshotCommandDispatcher.effect(for: .copy, in: terminalContext) == .ignore)
        }

        let failed = ScreenshotSessionState(phase: .failed, hasSelection: true)
        precondition(allCommands.allSatisfy { failed.canPerform($0) })
        precondition(failed.canHandlePointerInput)

        var operationTokens = ScreenshotOperationTokens()
        let recaptureToken = operationTokens.start(.windowRecapture)
        precondition(operationTokens.isCurrent(recaptureToken))
        precondition(recaptureToken.kind == .windowRecapture)
        let translationToken = operationTokens.start(.translation)
        precondition(!operationTokens.isCurrent(recaptureToken))
        precondition(operationTokens.isCurrent(translationToken))
        operationTokens.invalidate()
        precondition(!operationTokens.isCurrent(translationToken))
        let ocrToken = operationTokens.start(.ocr)
        precondition(operationTokens.isCurrent(ocrToken))
        precondition(ocrToken.generation == operationTokens.currentGeneration)
    }
}
