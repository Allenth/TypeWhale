import AppKit

extension NSView {
    /// 把当前真实视图缓存为静态图片；用于设置页预览，不参与生产展示。
    func typeWhaleSnapshotImage() -> NSImage? {
        layoutSubtreeIfNeeded()
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
enum CapsuleThemeSnapshotFactory {
    private static let canvasSize = NSSize(width: 320, height: 180)

    static func makeSnapshot(for kind: ThemePreviewTile.Kind) -> NSImage? {
        switch kind {
        case .classic:
            return makeClassicSnapshot()
        case .notch:
            let presenter = NotchPreviewPresenter()
            guard let snapshot = presenter.makeThemePreviewSnapshot(
                text: "正在实时识别你的声音"
            ) else {
                return nil
            }
            return compose([snapshot], background: UITheme.waterInkBackground)
        case .minimalBlack:
            let presenter = MinimalBlackPreviewPresenter()
            guard let snapshot = presenter.makeThemePreviewSnapshot(
                text: "语音输入会在这里实时出现"
            ) else {
                return nil
            }
            return compose([snapshot], background: UITheme.waterInkBackground)
        }
    }

    private static func makeClassicSnapshot() -> NSImage? {
        let configurations: [(PreviewAccent, String)] = [
            (.normal, "原文"),
            (.ideaPill, "闪念"),
            (.openClaw, "OpenClaw"),
        ]
        let snapshots = configurations.compactMap { accent, modeName in
            RecordingPanel().makeThemePreviewSnapshot(
                accent: accent,
                modeName: modeName
            )
        }
        guard snapshots.count == configurations.count else { return nil }
        return compose(snapshots, background: UITheme.waterInkBackground)
    }

    private static func compose(_ snapshots: [NSImage], background: NSColor) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let outerInset: CGFloat = 10
        let gap: CGFloat = snapshots.count > 1 ? 5 : 0
        let availableHeight = canvasSize.height - outerInset * 2 - gap * CGFloat(max(0, snapshots.count - 1))
        let rowHeight = availableHeight / CGFloat(max(1, snapshots.count))

        for (index, snapshot) in snapshots.enumerated() {
            let row = NSRect(
                x: outerInset,
                y: canvasSize.height - outerInset - CGFloat(index + 1) * rowHeight - CGFloat(index) * gap,
                width: canvasSize.width - outerInset * 2,
                height: rowHeight
            )
            drawAspectFit(snapshot, in: row)
        }
        image.unlockFocus()
        return image
    }

    private static func drawAspectFit(_ image: NSImage, in rect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let destination = NSRect(
            x: rect.midX - image.size.width * scale / 2,
            y: rect.midY - image.size.height * scale / 2,
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
