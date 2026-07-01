import AppKit

@main
struct RecordingCapsuleHealthBorderRenderCheck {
    @MainActor
    static func main() {
        let size = NSSize(width: 220, height: 48)
        let view = RecordingCapsuleView(frame: NSRect(origin: .zero, size: size))
        view.ollamaHealthBorderActive = true
        view.update(state: "录音中", draft: nil, bands: [0.35, 0.68, 0.52, 0.82, 0.45])

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            preconditionFailure("Expected bitmap representation")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let samplePoints = [
            NSPoint(x: 5, y: size.height / 2),
            NSPoint(x: size.width - 5, y: size.height / 2),
            NSPoint(x: size.width / 2, y: 5),
            NSPoint(x: size.width / 2, y: size.height - 5),
        ]
        let healthPixels = samplePoints.compactMap { point in
            bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB)
        }
        precondition(!healthPixels.isEmpty, "Expected readable health border pixels")
        precondition(
            healthPixels.contains { color in
                color.greenComponent > color.redComponent
                    && color.greenComponent > color.blueComponent
                    && color.alphaComponent > 0.20
            },
            "Expected visible green health border pixels"
        )

        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/typewhale-health-capsule.png"))
        }
        print("RecordingCapsuleHealthBorderRenderCheck passed")
    }
}
