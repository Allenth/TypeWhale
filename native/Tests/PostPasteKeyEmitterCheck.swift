import ApplicationServices
import Foundation

@main
struct PostPasteKeyEmitterCheck {
    static func main() {
        var posted: [(CGKeyCode, CGEventFlags)] = []
        let emitter = SystemPostPasteKeyEmitter { keyCode, flags in
            posted.append((keyCode, flags))
            return true
        }

        precondition(emitter.emit(.none), "none should be a successful no-op")
        precondition(posted.isEmpty, "none must not post a key")

        precondition(emitter.emit(.returnKey), "return key should post")
        precondition(posted.count == 1)
        precondition(posted[0].0 == 36, "return must use macOS return key code 36")
        precondition(posted[0].1.isEmpty, "plain return must not include modifiers")

        posted.removeAll()
        precondition(emitter.emit(.commandReturn), "command-return should post")
        precondition(posted.count == 1)
        precondition(posted[0].0 == 36)
        precondition(
            posted[0].1 == .maskCommand,
            "command-return must include only the command modifier"
        )

        let failing = SystemPostPasteKeyEmitter { _, _ in false }
        precondition(
            !failing.emit(.returnKey),
            "event creation/posting failure must be reported"
        )
        print("PostPasteKeyEmitterCheck passed")
    }
}
