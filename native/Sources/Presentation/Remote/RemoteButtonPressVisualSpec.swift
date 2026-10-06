import CoreGraphics
import Foundation

enum RemoteButtonPressRegionShape: Equatable {
    case ellipse
    case roundedRect(radius: CGFloat)
}

struct RemoteButtonPressRegion: Equatable {
    let button: RemoteButton
    let normalizedRect: CGRect
    let shape: RemoteButtonPressRegionShape

    func rect(in photoRect: CGRect) -> CGRect {
        CGRect(
            x: photoRect.minX + normalizedRect.minX * photoRect.width,
            y: photoRect.minY + normalizedRect.minY * photoRect.height,
            width: normalizedRect.width * photoRect.width,
            height: normalizedRect.height * photoRect.height
        )
    }
}

enum RemoteButtonPressVisualSpec {
    static let minimumVisibleReleaseDelay: TimeInterval = 0.18

    static let regions: [RemoteButtonPressRegion] = [
        region(.power, x: 0.251, y: 0.070, width: 0.160, height: 0.058, shape: .ellipse),
        region(.voice, x: 0.589, y: 0.070, width: 0.160, height: 0.058, shape: .ellipse),
        region(.dpadUp, x: 0.390, y: 0.145, width: 0.220, height: 0.065),
        region(.dpadLeft, x: 0.285, y: 0.205, width: 0.160, height: 0.072),
        region(.center, x: 0.365, y: 0.193, width: 0.270, height: 0.098, shape: .ellipse),
        region(.dpadRight, x: 0.555, y: 0.205, width: 0.160, height: 0.072),
        region(.dpadDown, x: 0.390, y: 0.277, width: 0.220, height: 0.065),
        region(.back, x: 0.257, y: 0.347, width: 0.214, height: 0.077, shape: .ellipse),
        region(.volumeUp, x: 0.527, y: 0.345, width: 0.216, height: 0.083),
        region(.home, x: 0.257, y: 0.433, width: 0.214, height: 0.077, shape: .ellipse),
        region(.volumeDown, x: 0.527, y: 0.427, width: 0.216, height: 0.087),
        region(.menu, x: 0.257, y: 0.519, width: 0.214, height: 0.077, shape: .ellipse),
        region(.tv, x: 0.527, y: 0.519, width: 0.216, height: 0.077, shape: .ellipse),
    ]

    static func region(for button: RemoteButton) -> RemoteButtonPressRegion? {
        regions.first { $0.button == button }
    }

    private static func region(
        _ button: RemoteButton,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        shape: RemoteButtonPressRegionShape? = nil
    ) -> RemoteButtonPressRegion {
        RemoteButtonPressRegion(
            button: button,
            normalizedRect: CGRect(x: x, y: y, width: width, height: height),
            shape: shape ?? .roundedRect(radius: 0.45)
        )
    }
}
