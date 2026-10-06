import Foundation

@main
struct BoundedVoiceProbeBacklogCheck {
    static func main() {
        var backlog = BoundedVoiceProbeBacklog<String>(capacity: 3)
        precondition(backlog.enqueue("silence-before"))
        precondition(backlog.enqueue("short-speech"))
        precondition(backlog.enqueue("silence-after"))
        precondition(!backlog.enqueue("overflow"), "overflow must fail closed instead of overwriting speech evidence")
        precondition(backlog.dequeue() == "silence-before")
        precondition(backlog.dequeue() == "short-speech", "FIFO order must preserve a short speech window")
        precondition(backlog.dequeue() == "silence-after")
        precondition(backlog.dequeue() == nil)

        _ = backlog.enqueue("old-session")
        backlog.removeAll()
        precondition(backlog.isEmpty, "a new recording must clear the old probe backlog")

        print("BoundedVoiceProbeBacklogCheck passed")
    }
}
