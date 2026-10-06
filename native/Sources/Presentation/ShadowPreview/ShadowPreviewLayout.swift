import CoreGraphics

struct ShadowPreviewLayout {
    static func frame(
        productionFrame: CGRect,
        shadowSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        edgeInset: CGFloat = 12
    ) -> CGRect {
        let safeMinX = visibleFrame.minX + edgeInset
        let safeMaxX = visibleFrame.maxX - edgeInset - shadowSize.width
        let centeredX = productionFrame.midX - shadowSize.width / 2
        let x = min(max(centeredX, safeMinX), max(safeMinX, safeMaxX))

        let belowY = productionFrame.minY - gap - shadowSize.height
        let aboveY = productionFrame.maxY + gap
        let fitsBelow = belowY >= visibleFrame.minY
        let fitsAbove = aboveY + shadowSize.height <= visibleFrame.maxY
        let y: CGFloat
        if fitsBelow {
            y = belowY
        } else if fitsAbove {
            y = aboveY
        } else {
            let belowSpace = productionFrame.minY - visibleFrame.minY
            let aboveSpace = visibleFrame.maxY - productionFrame.maxY
            y = belowSpace >= aboveSpace
                ? visibleFrame.minY
                : visibleFrame.maxY - shadowSize.height
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: shadowSize)
    }
}
