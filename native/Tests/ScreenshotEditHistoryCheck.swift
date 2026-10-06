import Foundation

@main
struct ScreenshotEditHistoryCheck {
    static func main() {
        var history = ScreenshotEditHistory<String>()
        precondition(history.items.isEmpty)
        precondition(!history.canUndo)
        precondition(!history.canRedo)

        history.append("rectangle")
        history.append("arrow")
        precondition(history.items == ["rectangle", "arrow"])
        precondition(history.canUndo)
        precondition(!history.canRedo)

        precondition(history.undo() == "arrow")
        precondition(history.items == ["rectangle"])
        precondition(history.canRedo)

        precondition(history.redo() == "arrow")
        precondition(history.items == ["rectangle", "arrow"])
        precondition(!history.canRedo)

        precondition(history.undo() == "arrow")
        history.append("nested rectangle")
        precondition(history.items == ["rectangle", "nested rectangle"])
        precondition(!history.canRedo, "Adding a new markup after undo must clear redo history")

        history.removeAll()
        precondition(history.items.isEmpty)
        precondition(!history.canUndo)
        precondition(!history.canRedo)

        print("ScreenshotEditHistoryCheck passed")
    }
}
