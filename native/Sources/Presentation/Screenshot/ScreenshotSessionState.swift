import Foundation

enum ScreenshotToolbarCommand: CaseIterable {
    case copy
    case save
    case ocr
    case translate
    case archive
    case annotate
    case rectangle
    case arrow
    case pen
    case text
    case mosaic
    case undo
    case redo
    case done
    case cancel
}

enum ScreenshotAnnotationTool: Equatable {
    case rectangle
    case arrow
    case pen
    case text
    case mosaic
}

struct ScreenshotCommandContext: Equatable {
    var sessionState: ScreenshotSessionState
    var hasUsableSelection: Bool
    var operationGeneration: Int = 0
    var isAnnotating: Bool = false
    var activeAnnotationTool: ScreenshotAnnotationTool = .rectangle
    var canUndo: Bool = false
    var canRedo: Bool = false
}

enum ScreenshotCommandEffect: Equatable {
    case copy
    case save
    case ocr
    case translate
    case archive
    case startAnnotation(ScreenshotAnnotationTool)
    case selectAnnotationTool(ScreenshotAnnotationTool)
    case undo
    case redo
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
        guard effectiveState(for: context).canPerform(command) else { return false }
        switch command {
        case .undo:
            return context.canUndo
        case .redo:
            return context.canRedo
        case .copy, .save, .ocr, .translate, .archive, .annotate, .rectangle, .arrow, .pen, .text, .mosaic, .done, .cancel:
            return true
        }
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
        case .archive:
            return .archive
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
        case .mosaic:
            return .selectAnnotationTool(.mosaic)
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .done:
            return .done
        case .cancel:
            return .cancel
        }
    }
}

struct ScreenshotEditHistory<Item> {
    private(set) var items: [Item] = []
    private var redoItems: [Item] = []

    var canUndo: Bool { !items.isEmpty }
    var canRedo: Bool { !redoItems.isEmpty }

    mutating func append(_ item: Item) {
        items.append(item)
        redoItems.removeAll()
    }

    mutating func removeAll() {
        items.removeAll()
        redoItems.removeAll()
    }

    @discardableResult
    mutating func undo() -> Item? {
        guard let item = items.popLast() else { return nil }
        redoItems.append(item)
        return item
    }

    @discardableResult
    mutating func redo() -> Item? {
        guard let item = redoItems.popLast() else { return nil }
        items.append(item)
        return item
    }
}

enum ScreenshotToolbarLayout {
    static let minimumButtonWidth: CGFloat = 50
    static let maximumButtonWidth: CGFloat = 68

    static func fixedWidth(
        actionCount: Int,
        spacing: CGFloat,
        separatorWidth: CGFloat,
        groupSpacing: CGFloat,
        outerPadding: CGFloat
    ) -> CGFloat {
        CGFloat(max(0, actionCount - 2)) * spacing
            + groupSpacing * 2
            + separatorWidth
            + outerPadding
    }

    static func buttonWidth(boundsWidth: CGFloat, actionCount: Int, fixedWidth: CGFloat) -> CGFloat {
        guard actionCount > 0 else { return minimumButtonWidth }
        let availableButtonWidth = floor((boundsWidth - 16 - fixedWidth) / CGFloat(actionCount))
        return min(maximumButtonWidth, max(minimumButtonWidth, availableButtonWidth))
    }

    static func totalWidth(actionCount: Int, buttonWidth: CGFloat, fixedWidth: CGFloat) -> CGFloat {
        CGFloat(actionCount) * buttonWidth + fixedWidth
    }
}

enum ScreenshotOperationKind: Equatable {
    case windowRecapture
    case ocr
    case translation
    case archive
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
