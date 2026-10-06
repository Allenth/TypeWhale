import AppKit
import CoreGraphics

@main
struct ScreenshotGaussianBlurCheck {
    static func main() {
        guard let image = checkerboardImage(width: 48, height: 48, tileSize: 4) else {
            preconditionFailure("Expected checkerboard image")
        }
        let rect = CGRect(x: 8, y: 8, width: 32, height: 32)
        guard let blurred = ScreenshotGaussianBlurRenderer.blurredPatch(from: image, rect: rect, radius: 7) else {
            preconditionFailure("Expected blurred patch")
        }
        precondition(blurred.width == Int(rect.width))
        precondition(blurred.height == Int(rect.height))

        let originalSample = sampleGray(image, x: 24, y: 24)
        let blurredSample = sampleGray(blurred, x: blurred.width / 2, y: blurred.height / 2)
        precondition(originalSample < 0.05 || originalSample > 0.95)
        precondition(
            blurredSample > 0.18 && blurredSample < 0.82,
            "Gaussian blur should turn high-contrast checker pixels into mixed gray"
        )

        print("ScreenshotGaussianBlurCheck passed")
    }

    private static func checkerboardImage(width: Int, height: Int, tileSize: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let isWhite = ((x / tileSize) + (y / tileSize)).isMultiple(of: 2)
                let offset = ((y * width) + x) * 4
                let value: UInt8 = isWhite ? 255 : 0
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func sampleGray(_ image: CGImage, x: Int, y: Int) -> CGFloat {
        let width = image.width
        let height = image.height
        precondition(x >= 0 && x < width && y >= 0 && y < height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Expected readable pixel context")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = ((y * width) + x) * 4
        let red = CGFloat(pixels[offset]) / 255
        let green = CGFloat(pixels[offset + 1]) / 255
        let blue = CGFloat(pixels[offset + 2]) / 255
        return (red + green + blue) / 3
    }
}
