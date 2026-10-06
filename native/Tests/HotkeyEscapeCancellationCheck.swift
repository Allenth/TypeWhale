import Foundation

enum RecognitionLanguageMode {
    case chinese
}

@main
enum HotkeyEscapeCancellationCheck {
    static func main() {
        var gate = EscapeCancellationGate()
        var cancelCalls = 0
        precondition(gate.handle(keyCode: 53, isDown: true) {
            cancelCalls += 1
            return true
        })
        precondition(gate.handle(keyCode: 53, isDown: false) {
            cancelCalls += 1
            return false
        })
        precondition(cancelCalls == 1)
        precondition(!gate.handle(keyCode: 53, isDown: true) { false })
        precondition(!gate.handle(keyCode: 12, isDown: true) { true })
        print("HotkeyEscapeCancellationCheck passed")
    }
}
