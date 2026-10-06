import AppKit

@main
struct RecordingCapsuleOpenClawGlowCheck {
    @MainActor
    static func main() {
        let plainView = RecordingCapsuleView(frame: NSRect(origin: .zero, size: NSSize(width: 176, height: 42)))
        let plainPreferred = plainView.preferredSize

        let openClawViewForSize = RecordingCapsuleView(frame: NSRect(origin: .zero, size: plainPreferred))
        openClawViewForSize.innerGlow = .openClaw
        let openClawPreferred = openClawViewForSize.preferredSize
        precondition(
            abs((openClawPreferred.width - plainPreferred.width) - 18) < 0.1,
            "OpenClaw capsule should keep the same body width and reserve intersecting badge space"
        )
        precondition(
            abs((openClawPreferred.height - plainPreferred.height) - 9) < 0.1,
            "OpenClaw capsule should keep the same body height and only reserve top badge overhang"
        )

        let size = openClawPreferred
        let view = RecordingCapsuleView(frame: NSRect(origin: .zero, size: size))
        view.statusBorderColor = RecordingCapsuleView.openClawBorderColor
        view.innerGlow = .openClaw
        view.openClawConnectionStatus = .connected

        let bitmap = render(view, size: size)

        let center = averageColor(
            in: bitmap,
            rect: NSRect(x: 72, y: 15, width: 76, height: 18)
        )
        precondition(
            center.redBias > 0.05 && center.alpha > 0.02,
            "OpenClaw glow should reach the capsule center with a red tint"
        )

        let bodyRightEdge = averageColor(
            in: bitmap,
            rect: NSRect(x: Int(plainPreferred.width) - 4, y: 15, width: 3, height: 12)
        )
        let badgeBodyIntersection = averageColor(
            in: bitmap,
            rect: NSRect(x: Int(plainPreferred.width) - 10, y: Int(size.height) - 28, width: 8, height: 10)
        )
        let badge = averageColor(
            in: bitmap,
            rect: NSRect(x: Int(plainPreferred.width) - 3, y: Int(size.height) - 28, width: 10, height: 10)
        )
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/typewhale-openclaw-capsule-glow.png"))
        }
        precondition(
            bodyRightEdge.alpha > 0.05,
            "OpenClaw red capsule body should extend to the same right edge as the normal capsule"
        )
        precondition(
            badgeBodyIntersection.redBias > 0.12 && badgeBodyIntersection.alpha > 0.10,
            "OpenClaw lobster badge should intersect the capsule body at the top-right corner"
        )
        precondition(
            badge.redBias > 0.20 && badge.alpha > 0.10,
            "OpenClaw lobster badge should be visibly red outside the capsule body when connected"
        )

        let checkingView = RecordingCapsuleView(frame: NSRect(origin: .zero, size: size))
        checkingView.innerGlow = .openClaw
        checkingView.openClawConnectionStatus = .checking
        let checkingBadge = averageColor(
            in: render(checkingView, size: size),
            rect: NSRect(x: Int(plainPreferred.width) - 3, y: Int(size.height) - 28, width: 10, height: 10)
        )
        precondition(
            checkingBadge.yellowBias > 0.18 && checkingBadge.alpha > 0.10,
            "OpenClaw lobster badge should be yellow while checking connection"
        )

        let unavailableView = RecordingCapsuleView(frame: NSRect(origin: .zero, size: size))
        unavailableView.innerGlow = .openClaw
        unavailableView.openClawConnectionStatus = .unavailable
        let unavailableBadge = averageColor(
            in: render(unavailableView, size: size),
            rect: NSRect(x: Int(plainPreferred.width) - 3, y: Int(size.height) - 28, width: 10, height: 10)
        )
        precondition(
            unavailableBadge.brightness < 0.28 && unavailableBadge.alpha > 0.10,
            "OpenClaw lobster badge should be dark when connection is unavailable"
        )
        print("RecordingCapsuleOpenClawGlowCheck passed")
    }

    private static func render(_ view: RecordingCapsuleView, size: NSSize) -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            preconditionFailure("Expected bitmap representation")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func averageColor(in bitmap: NSBitmapImageRep, rect: NSRect) -> SampledColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var count: CGFloat = 0

        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                alpha += color.alphaComponent
                count += 1
            }
        }

        precondition(count > 0, "Expected at least one sampled pixel")
        return SampledColor(red: red / count, green: green / count, blue: blue / count, alpha: alpha / count)
    }

    private struct SampledColor {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        var redBias: CGFloat {
            red - ((green + blue) / 2)
        }

        var yellowBias: CGFloat {
            min(red, green) - blue
        }

        var brightness: CGFloat {
            (red + green + blue) / 3
        }
    }
}
