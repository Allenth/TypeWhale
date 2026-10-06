import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("usage: AppIconGeometryCheck.swift <icon.png>\n", stderr)
    exit(2)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard
    let source = CGImageSourceCreateWithURL(iconURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let data = image.dataProvider?.data,
    let bytes = CFDataGetBytePtr(data),
    image.bitsPerPixel == 32
else {
    fputs("Unable to read a 32-bit RGBA app icon.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = image.bitsPerPixel / 8
let bytesPerRow = image.bytesPerRow
var minX = width
var minY = height
var maxX = -1
var maxY = -1

for y in 0..<height {
    for x in 0..<width {
        let alpha = bytes[y * bytesPerRow + x * bytesPerPixel + 3]
        if alpha > 8 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    fputs("App icon has no visible pixels.\n", stderr)
    exit(1)
}

let visibleWidth = maxX - minX + 1
let visibleHeight = maxY - minY + 1
let widthRatio = Double(visibleWidth) / Double(width)
let heightRatio = Double(visibleHeight) / Double(height)
let acceptedRatio = 0.79...0.86
let widthPercent = String(format: "%.1f", widthRatio * 100)
let heightPercent = String(format: "%.1f", heightRatio * 100)

guard acceptedRatio.contains(widthRatio), acceptedRatio.contains(heightRatio) else {
    fputs(
        "App icon visual bounds are \(visibleWidth)x\(visibleHeight) on \(width)x\(height) " +
        "(\(widthPercent)% x \(heightPercent)%); expected 79–86%.\n",
        stderr
    )
    exit(1)
}

print(
    "AppIconGeometryCheck passed: bounds \(visibleWidth)x\(visibleHeight) " +
    "(\(widthPercent)% x \(heightPercent)%)."
)
