import AppKit

/// 刘海/虚拟刘海几何：给出某屏幕上「刘海区、左侧区、右侧区」的矩形（屏幕坐标，原点左下）。
///
/// - 真刘海：用系统 `safeAreaInsets.top` 判定，`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
///   给出刘海两侧的可用区，刘海区夹在中间。
/// - 无刘海屏：合成一个顶部居中的「虚拟刘海区」（宽度固定、高度取菜单栏高度），
///   左右区为其两侧的菜单栏带，让刘海主题在所有 Mac 上都能用。
struct NotchGeometry {
    let screen: NSScreen
    let notchRect: NSRect
    let leftArea: NSRect
    let rightArea: NSRect
    let hasPhysicalNotch: Bool

    static func current(virtualNotchWidth: CGFloat = 200) -> NotchGeometry? {
        guard let screen = NSScreen.main else { return nil }
        let full = screen.frame
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchRect = NSRect(
                x: left.maxX,
                y: full.maxY - topInset,
                width: max(0, right.minX - left.maxX),
                height: topInset
            )
            return NotchGeometry(
                screen: screen,
                notchRect: notchRect,
                leftArea: left,
                rightArea: right,
                hasPhysicalNotch: true
            )
        }

        // 虚拟刘海：顶部居中，高度取菜单栏高度（visibleFrame 不含菜单栏）。
        let menuBarHeight = max(24, full.maxY - screen.visibleFrame.maxY)
        let notchRect = NSRect(
            x: full.midX - virtualNotchWidth / 2,
            y: full.maxY - menuBarHeight,
            width: virtualNotchWidth,
            height: menuBarHeight
        )
        let leftArea = NSRect(
            x: full.minX, y: notchRect.minY,
            width: max(0, notchRect.minX - full.minX), height: menuBarHeight
        )
        let rightArea = NSRect(
            x: notchRect.maxX, y: notchRect.minY,
            width: max(0, full.maxX - notchRect.maxX), height: menuBarHeight
        )
        return NotchGeometry(
            screen: screen,
            notchRect: notchRect,
            leftArea: leftArea,
            rightArea: rightArea,
            hasPhysicalNotch: false
        )
    }
}
