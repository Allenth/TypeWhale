import Foundation
import CoreGraphics

@main
struct ShadowPreviewLayoutCheck {
    static func main() {
        prefersCenteredPlacementBelowProductionCapsule()
        fallsBackAboveNearBottomEdge()
        clampsToLeftAndRightSafeInsets()
        respectsNotchScreenVisibleFrame()
        print("ShadowPreviewLayoutCheck passed")
    }

    private static func prefersCenteredPlacementBelowProductionCapsule() {
        let production = CGRect(x: 400, y: 500, width: 200, height: 40)
        let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let result = ShadowPreviewLayout.frame(
            productionFrame: production,
            shadowSize: CGSize(width: 180, height: 36),
            visibleFrame: visible
        )

        precondition(result == CGRect(x: 410, y: 456, width: 180, height: 36))
        assertSafe(result, production: production, visible: visible)
    }

    private static func fallsBackAboveNearBottomEdge() {
        let production = CGRect(x: 400, y: 10, width: 200, height: 40)
        let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let result = ShadowPreviewLayout.frame(
            productionFrame: production,
            shadowSize: CGSize(width: 180, height: 36),
            visibleFrame: visible
        )

        precondition(result.origin.y == 58)
        assertSafe(result, production: production, visible: visible)
    }

    private static func clampsToLeftAndRightSafeInsets() {
        let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let leftProduction = CGRect(x: 0, y: 400, width: 100, height: 40)
        let left = ShadowPreviewLayout.frame(
            productionFrame: leftProduction,
            shadowSize: CGSize(width: 180, height: 36),
            visibleFrame: visible
        )
        precondition(left.minX == 12)
        assertSafe(left, production: leftProduction, visible: visible)

        let rightProduction = CGRect(x: 950, y: 400, width: 50, height: 40)
        let right = ShadowPreviewLayout.frame(
            productionFrame: rightProduction,
            shadowSize: CGSize(width: 180, height: 36),
            visibleFrame: visible
        )
        precondition(right.maxX == 988)
        assertSafe(right, production: rightProduction, visible: visible)
    }

    private static func respectsNotchScreenVisibleFrame() {
        let visible = CGRect(x: 0, y: 30, width: 1_512, height: 940)
        let production = CGRect(x: 656, y: 904, width: 200, height: 42)
        let result = ShadowPreviewLayout.frame(
            productionFrame: production,
            shadowSize: CGSize(width: 220, height: 38),
            visibleFrame: visible
        )

        precondition(result.origin == CGPoint(x: 646, y: 858))
        assertSafe(result, production: production, visible: visible)
    }

    private static func assertSafe(
        _ shadow: CGRect,
        production: CGRect,
        visible: CGRect
    ) {
        precondition(!shadow.intersects(production), "shadow must not overlap production capsule")
        precondition(shadow.minX >= visible.minX + 12)
        precondition(shadow.maxX <= visible.maxX - 12)
        precondition(shadow.minY >= visible.minY)
        precondition(shadow.maxY <= visible.maxY)
    }
}
