import AppKit

@main
struct RecordingCapsuleHealthBorderRenderCheck {
    @MainActor
    static func main() {
        let size = NSSize(width: 220, height: 48)
        let view = HealthBorderOverlayView(frame: NSRect(origin: .zero, size: size))
        view.isActive = true

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            preconditionFailure("Expected bitmap representation")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)

        var healthPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.greenComponent > color.redComponent,
                   color.greenComponent > color.blueComponent,
                   color.alphaComponent > 0.06 {
                    healthPixelCount += 1
                }
            }
        }
        precondition(
            healthPixelCount > 100,
            "Expected visible green health border pixels"
        )

        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/typewhale-health-border-overlay.png"))
        }
        print("RecordingCapsuleHealthBorderRenderCheck passed")
    }
}
