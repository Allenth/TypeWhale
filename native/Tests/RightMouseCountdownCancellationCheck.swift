import Foundation

@main
enum RightMouseCountdownCancellationCheck {
    static func main() {
        consumesOnlyTheCancelledRightMousePair()
        passesThroughWhenThereIsNoCountdown()
        passesThroughOtherMouseButtons()
        doesNotCancelTwiceForDuplicateDown()
        resetCannotLeaveRightMouseSuppressed()
        print("RightMouseCountdownCancellationCheck passed")
    }

    private static func consumesOnlyTheCancelledRightMousePair() {
        var gate = RightMouseCancellationGate()
        var cancellations = 0
        precondition(gate.handle(buttonNumber: 1, isDown: true) {
            cancellations += 1
            return true
        })
        precondition(gate.handle(buttonNumber: 1, isDown: false) {
            cancellations += 1
            return false
        })
        precondition(cancellations == 1)
        precondition(!gate.handle(buttonNumber: 1, isDown: false) { true })
    }

    private static func passesThroughWhenThereIsNoCountdown() {
        var gate = RightMouseCancellationGate()
        var cancellations = 0
        precondition(!gate.handle(buttonNumber: 1, isDown: true) {
            cancellations += 1
            return false
        })
        precondition(!gate.handle(buttonNumber: 1, isDown: false) { true })
        precondition(cancellations == 1)
    }

    private static func passesThroughOtherMouseButtons() {
        var gate = RightMouseCancellationGate()
        for button in [0, 2, 3, 4, 5] {
            precondition(!gate.handle(buttonNumber: button, isDown: true) { true })
            precondition(!gate.handle(buttonNumber: button, isDown: false) { true })
        }
    }

    private static func doesNotCancelTwiceForDuplicateDown() {
        var gate = RightMouseCancellationGate()
        var cancellations = 0
        precondition(gate.handle(buttonNumber: 1, isDown: true) {
            cancellations += 1
            return true
        })
        precondition(gate.handle(buttonNumber: 1, isDown: true) {
            cancellations += 1
            return true
        })
        precondition(cancellations == 1)
        precondition(gate.handle(buttonNumber: 1, isDown: false) { false })
    }

    private static func resetCannotLeaveRightMouseSuppressed() {
        var gate = RightMouseCancellationGate()
        precondition(gate.handle(buttonNumber: 1, isDown: true) { true })
        gate.reset()
        precondition(!gate.handle(buttonNumber: 1, isDown: false) { true })
    }
}
