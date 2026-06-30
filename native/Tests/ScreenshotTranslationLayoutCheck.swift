import AppKit
import Foundation

@main
struct ScreenshotTranslationLayoutCheck {
    static func main() {
        let compactRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 50, y: 40, width: 38, height: 18),
            text: "设置",
            selectionSize: NSSize(width: 300, height: 200)
        )
        precondition(compactRect.width < 80)
        precondition(compactRect.width >= 24)
        precondition(compactRect.height <= 34)
        precondition(abs(compactRect.minX - 48) <= 0.5)

        let longerRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 20, y: 80, width: 120, height: 20),
            text: "保存到配置的截图文件夹",
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(longerRect.width <= 160)
        precondition(longerRect.height <= 38)
        precondition(longerRect.minX >= 0)
        precondition(longerRect.maxX <= 320)
        precondition(abs(longerRect.minX - 18) <= 0.5)

        let rightEdgeRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 285, y: 120, width: 60, height: 20),
            text: "非常靠右的按钮",
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(rightEdgeRect.maxX <= 320)
        precondition(rightEdgeRect.minX < 283)
        precondition(rightEdgeRect.minX >= 0)

        let emptyRect = ScreenshotTranslationLayout.blockRect(
            alignedWith: NSRect(x: 400, y: 120, width: 60, height: 20),
            text: "越界",
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(emptyRect == .zero)

        precondition(ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 100, height: 80)) == 5)
        precondition(ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 900, height: 500)) == 30)

        let backdropRect = ScreenshotTranslationLayout.backdropRect(
            sourceRects: [
                NSRect(x: 20, y: 80, width: 120, height: 20),
                NSRect(x: 22, y: 52, width: 88, height: 18),
            ],
            blockRects: [
                longerRect,
                NSRect(x: 20, y: 48, width: 96, height: 24),
            ],
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(backdropRect.minX <= ScreenshotTranslationLayout.leadingMargin(for: NSSize(width: 320, height: 180)))
        precondition(backdropRect.maxX >= longerRect.maxX)
        precondition(backdropRect.minY <= 44)
        precondition(backdropRect.maxY >= 104)
        precondition(backdropRect.maxX <= 320)
        precondition(backdropRect.maxY <= 180)

        let constrainedHeight: CGFloat = 38
        let fittingFontSize = ScreenshotTranslationLayout.fontSize(
            fitting: "保存到配置的截图文件夹",
            width: 120,
            maxHeight: constrainedHeight,
            selectionSize: NSSize(width: 320, height: 180)
        )
        let measuredHeight = ScreenshotTranslationLayout.textHeight(
            "保存到配置的截图文件夹",
            width: 120,
            fontSize: fittingFontSize,
            selectionSize: NSSize(width: 320, height: 180)
        )
        precondition(fittingFontSize < 14)
        precondition(measuredHeight <= constrainedHeight)
    }
}
