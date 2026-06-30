import AppKit

enum ScreenshotTranslationLayout {
    static func blockRect(alignedWith lineRect: NSRect, text: String, selectionSize: NSSize) -> NSRect {
        let selectionBounds = NSRect(origin: .zero, size: selectionSize)
        let sourceRect = lineRect.insetBy(dx: -2, dy: -1).intersection(selectionBounds)
        guard !sourceRect.isEmpty else { return .zero }

        let leadingMargin = leadingMargin(for: selectionSize)
        let trailingMargin = leadingMargin
        let availableWidth = max(24, selectionSize.width - leadingMargin - trailingMargin)
        let baseFontSize = baseFontSize(for: selectionSize)
        let naturalWidth = ceil(singleLineTextWidth(text, fontSize: baseFontSize)) + 12
        let minimumWidth = min(availableWidth, max(24, min(sourceRect.width, naturalWidth)))
        let expansionAllowance = max(18, sourceRect.width * 0.28)
        let maximumWidth = min(availableWidth, max(minimumWidth, sourceRect.width + expansionAllowance))
        let width = min(max(minimumWidth, naturalWidth), maximumWidth)

        let maxHeight = max(16, min(selectionSize.height, sourceRect.height * 1.55 + 6))
        let fontSize = fontSize(fitting: text, width: width, maxHeight: maxHeight, selectionSize: selectionSize)
        let measuredHeight = textHeight(text, width: width, fontSize: fontSize, selectionSize: selectionSize)
        let height = min(max(measuredHeight, sourceRect.height + 2, 16), maxHeight)

        let x = min(leadingMargin, max(0, selectionSize.width - width))
        let y = min(max(sourceRect.midY - height / 2, 0), max(0, selectionSize.height - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func leadingMargin(for selectionSize: NSSize) -> CGFloat {
        min(30, max(5, selectionSize.width * 0.04))
    }

    static func backdropRect(sourceRects: [NSRect], blockRects: [NSRect], selectionSize: NSSize) -> NSRect {
        let selectionBounds = NSRect(origin: .zero, size: selectionSize)
        let paddedSourceRects = sourceRects.map {
            $0.insetBy(dx: -4, dy: -2).intersection(selectionBounds)
        }
        let paddedBlockRects = blockRects.map {
            $0.insetBy(dx: -3, dy: -2).intersection(selectionBounds)
        }
        guard let union = unionRect(paddedSourceRects + paddedBlockRects) else { return .zero }
        return union.insetBy(dx: -5, dy: -4).intersection(selectionBounds)
    }

    static func fontSize(fitting text: String, width: CGFloat, maxHeight: CGFloat, selectionSize: NSSize) -> CGFloat {
        var size = baseFontSize(for: selectionSize)
        while size >= 8 {
            if textHeight(text, width: width, fontSize: size, selectionSize: selectionSize) <= maxHeight {
                return size
            }
            size -= 1
        }
        return 8
    }

    static func textHeight(_ text: String, width: CGFloat, fontSize: CGFloat, selectionSize: NSSize) -> CGFloat {
        let inset = textInset(width: width, height: max(1, selectionSize.height))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = selectionSize.height < 90 ? 0.5 : 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .paragraphStyle: paragraph,
        ]
        let textWidth = max(1, width - inset * 2)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(measured.height) + inset * 2
    }

    static func textInset(for rect: NSRect) -> CGFloat {
        textInset(width: rect.width, height: rect.height)
    }

    private static func baseFontSize(for selectionSize: NSSize) -> CGFloat {
        selectionSize.width < 320 || selectionSize.height < 180 ? 12 : 14
    }

    private static func singleLineTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
        ]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private static func unionRect(_ rects: [NSRect]) -> NSRect? {
        rects.reduce(nil) { partial, rect in
            guard !rect.isEmpty else { return partial }
            return partial?.union(rect) ?? rect
        }
    }

    private static func textInset(width: CGFloat, height: CGFloat) -> CGFloat {
        width < 160 || height < 72 ? 4 : 6
    }
}
