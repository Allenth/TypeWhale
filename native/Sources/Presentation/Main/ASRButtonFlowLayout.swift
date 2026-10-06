import AppKit

enum ASRButtonFlowLayout {
    struct Result {
        let frames: [CGRect]
        let height: CGFloat
    }

    static let horizontalSpacing: CGFloat = 6
    static let verticalSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 28
    static let insets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

    static func layout(containerWidth: CGFloat, itemWidths: [CGFloat]) -> Result {
        guard !itemWidths.isEmpty else { return Result(frames: [], height: 0) }

        let rightEdge = max(insets.left, containerWidth - insets.right)
        let availableWidth = max(0, rightEdge - insets.left)
        var x = insets.left
        var y = insets.top
        var frames: [CGRect] = []

        for requestedWidth in itemWidths {
            let width = min(max(0, requestedWidth), availableWidth)
            if x > insets.left, x + width > rightEdge {
                x = insets.left
                y += rowHeight + verticalSpacing
            }
            frames.append(CGRect(x: x, y: y, width: width, height: rowHeight))
            x += width + horizontalSpacing
        }

        return Result(
            frames: frames,
            height: y + rowHeight + insets.bottom
        )
    }
}
