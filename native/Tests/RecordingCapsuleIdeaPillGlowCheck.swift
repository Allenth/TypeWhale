import AppKit

@main
struct RecordingCapsuleIdeaPillGlowCheck {
    @MainActor
    static func main() {
        let size = NSSize(width: 220, height: 48)
        let view = RecordingCapsuleView(frame: NSRect(origin: .zero, size: size))
        view.statusBorderColor = RecordingCapsuleView.ideaPillBorderColor
        view.innerGlow = .ideaPill

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            preconditionFailure("Expected bitmap representation")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let center = averageColor(
            in: bitmap,
            rect: NSRect(x: 72, y: 15, width: 76, height: 18)
        )
        precondition(
            center.purpleBias > 0.025 && center.alpha > 0.02,
            "Idea pill glow should reach the capsule center with a subtle purple tint"
        )

        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/typewhale-idea-pill-capsule-glow.png"))
        }
        print("RecordingCapsuleIdeaPillGlowCheck passed")
    }

    private static func averageColor(in bitmap: NSBitmapImageRep, rect: NSRect) -> SampledColor {
        averageColor(in: bitmap, rects: [rect])
    }

    private static func averageColor(in bitmap: NSBitmapImageRep, rects: [NSRect]) -> SampledColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var count: CGFloat = 0

        for rect in rects {
            let xRange = Int(rect.minX)..<Int(rect.maxX)
            let yRange = Int(rect.minY)..<Int(rect.maxY)
            for y in yRange {
                for x in xRange {
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
        }

        precondition(count > 0, "Expected at least one sampled pixel")
        return SampledColor(red: red / count, green: green / count, blue: blue / count, alpha: alpha / count)
    }

    private struct SampledColor {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        var purpleBias: CGFloat {
            ((red + blue) / 2) - green
        }
    }
}
