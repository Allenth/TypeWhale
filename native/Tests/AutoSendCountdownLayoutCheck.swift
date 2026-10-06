import Foundation
import CoreGraphics

@main
enum AutoSendCountdownLayoutCheck {
    static func main() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let capsule = CGRect(x: 350, y: 68, width: 300, height: 60)
        let size = CGSize(width: 244, height: 46)
        let above = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: capsule,
            visibleFrame: visible
        )
        precondition(above == CGPoint(x: 378, y: 75))

        let topCapsule = CGRect(x: 350, y: 750, width: 300, height: 40)
        let below = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: topCapsule,
            visibleFrame: visible
        )
        precondition(below == CGPoint(x: 378, y: 747))

        let fallback = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: nil,
            visibleFrame: visible
        )
        precondition(fallback == CGPoint(x: 378, y: 28))
        print("AutoSendCountdownLayoutCheck passed")
    }
}
