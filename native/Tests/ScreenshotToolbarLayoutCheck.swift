import Foundation

@main
struct ScreenshotToolbarLayoutCheck {
    static func main() {
        let actionCount = 13
        let fixedWidth = ScreenshotToolbarLayout.fixedWidth(
            actionCount: actionCount,
            spacing: 7,
            separatorWidth: 1,
            groupSpacing: 15,
            outerPadding: 14
        )
        let buttonWidth = ScreenshotToolbarLayout.buttonWidth(
            boundsWidth: 800,
            actionCount: actionCount,
            fixedWidth: fixedWidth
        )
        let totalWidth = ScreenshotToolbarLayout.totalWidth(
            actionCount: actionCount,
            buttonWidth: buttonWidth,
            fixedWidth: fixedWidth
        )

        precondition(buttonWidth >= 50)
        precondition(totalWidth <= 800 - 16, "Screenshot toolbar should fit a narrow 800pt overlay after adding mosaic")

        print("ScreenshotToolbarLayoutCheck passed")
    }
}
