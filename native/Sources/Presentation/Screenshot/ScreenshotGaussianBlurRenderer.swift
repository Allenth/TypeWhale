import CoreGraphics
import CoreImage

enum ScreenshotGaussianBlurRenderer {
    static let defaultRadius: CGFloat = 8

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: colorSpace as Any,
        .outputColorSpace: colorSpace as Any
    ])

    static func blurredPatch(from image: CGImage, rect: CGRect, radius: CGFloat = defaultRadius) -> CGImage? {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = rect.integral.intersection(imageRect)
        guard cropRect.width >= 1, cropRect.height >= 1 else { return nil }

        let input = CIImage(cgImage: image)
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: radius
            ])
            .cropped(to: cropRect)

        return context.createCGImage(blurred, from: cropRect, format: .RGBA8, colorSpace: colorSpace)
    }
}
