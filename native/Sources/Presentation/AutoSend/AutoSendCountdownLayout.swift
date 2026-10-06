import Foundation
import CoreGraphics

enum AutoSendCountdownLayout {
    static let fallbackBottomInset: CGFloat = 28

    static func origin(
        overlaySize: CGSize,
        capsuleFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGPoint {
        guard let capsuleFrame else {
            return clamp(
                CGPoint(
                    x: visibleFrame.midX - overlaySize.width / 2,
                    y: visibleFrame.minY + fallbackBottomInset
                ),
                overlaySize: overlaySize,
                visibleFrame: visibleFrame
            )
        }

        return clamp(
            CGPoint(
                x: capsuleFrame.midX - overlaySize.width / 2,
                y: capsuleFrame.midY - overlaySize.height / 2
            ),
            overlaySize: overlaySize,
            visibleFrame: visibleFrame
        )
    }

    private static func clamp(
        _ origin: CGPoint,
        overlaySize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - overlaySize.width
            ),
            y: min(
                max(origin.y, visibleFrame.minY),
                visibleFrame.maxY - overlaySize.height
            )
        )
    }
}
