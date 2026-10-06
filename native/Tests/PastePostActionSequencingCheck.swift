import Foundation

@main
struct PastePostActionSequencingCheck {
    static func main() {
        precondition(
            PostPasteActionSchedulingGate.shouldSchedule(.returnKey)
        )
        precondition(
            PostPasteActionSchedulingGate.shouldSchedule(.commandReturn)
        )
        precondition(
            !PostPasteActionSchedulingGate.shouldSchedule(.none)
        )
        print("PastePostActionSequencingCheck passed")
    }
}
