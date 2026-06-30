import Foundation

enum ScreenshotToolbarCommand: CaseIterable {
    case copy
    case save
    case ocr
    case translate
    case annotate
    case rectangle
    case arrow
    case pen
    case text
    case undo
    case done
    case cancel
}

enum ScreenshotAnnotationTool: Equatable {
    case rectangle
    case arrow
    case pen
    case text
}

struct ScreenshotCommandContext: Equatable {
    var sessionState: ScreenshotSessionState
    var hasUsableSelection: Bool
    var operationGeneration: Int = 0
    var isAnnotating: Bool = false
    var activeAnnotationTool: ScreenshotAnnotationTool = .rectangle
}

enum ScreenshotCommandEffect: Equatable {
    case copy
    case save
    case ocr
    case translate
    case startAnnotation(ScreenshotAnnotationTool)
    case selectAnnotationTool(ScreenshotAnnotationTool)
    case undo
    case done
    case cancel
    case ignore
}

enum ScreenshotCommandDispatcher {
    static func effectiveState(for context: ScreenshotCommandContext) -> ScreenshotSessionState {
        var state = context.sessionState
        state.hasSelection = context.hasUsableSelection
        return state
    }

    static func canPerform(_ command: ScreenshotToolbarCommand, in context: ScreenshotCommandContext) -> Bool {
        effectiveState(for: context).canPerform(command)
    }

    static func effect(for command: ScreenshotToolbarCommand, in context: ScreenshotCommandContext) -> ScreenshotCommandEffect {
        guard canPerform(command, in: context) else { return .ignore }
        switch command {
        case .copy:
            return .copy
        case .save:
            return .save
        case .ocr:
            return .ocr
        case .translate:
            return .translate
        case .annotate:
            return .startAnnotation(.rectangle)
        case .rectangle:
            return .selectAnnotationTool(.rectangle)
        case .arrow:
            return .selectAnnotationTool(.arrow)
        case .pen:
            return .selectAnnotationTool(.pen)
        case .text:
            return .selectAnnotationTool(.text)
        case .undo:
            return .undo
        case .done:
            return .done
        case .cancel:
            return .cancel
        }
    }
}

enum ScreenshotOperationKind: Equatable {
    case windowRecapture
    case ocr
    case translation
    case transientStatus
}

struct ScreenshotOperationToken: Equatable {
    let generation: Int
    let kind: ScreenshotOperationKind
}

struct ScreenshotOperationTokens: Equatable {
    private(set) var currentGeneration = 0

    mutating func start(_ kind: ScreenshotOperationKind) -> ScreenshotOperationToken {
        currentGeneration += 1
        return ScreenshotOperationToken(generation: currentGeneration, kind: kind)
    }

    mutating func invalidate() {
        currentGeneration += 1
    }

    func isCurrent(_ token: ScreenshotOperationToken) -> Bool {
        token.generation == currentGeneration
    }
}

struct ScreenshotSessionState: Equatable {
    enum Phase: Equatable {
        case idle
        case selecting
        case selected
        case windowRecapturePending
        case translating
        case completed
        case cancelled
        case failed
    }

    var phase: Phase = .idle
    var hasSelection = false

    var canHandlePointerInput: Bool {
        switch phase {
        case .idle, .selecting, .selected, .failed:
            return true
        case .windowRecapturePending, .translating, .completed, .cancelled:
            return false
        }
    }

    var canAdjustSelection: Bool {
        switch phase {
        case .selecting, .selected:
            return hasSelection
        case .idle, .windowRecapturePending, .translating, .completed, .cancelled, .failed:
            return false
        }
    }

    func canPerform(_ command: ScreenshotToolbarCommand) -> Bool {
        switch phase {
        case .idle:
            return hasSelection || command == .cancel
        case .selecting:
            return hasSelection || command == .cancel
        case .selected, .failed:
            guard hasSelection else { return command == .cancel }
            return true
        case .windowRecapturePending, .translating:
            return command == .cancel
        case .completed, .cancelled:
            return false
        }
    }
}
