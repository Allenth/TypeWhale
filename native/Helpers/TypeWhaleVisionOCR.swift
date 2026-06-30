import AppKit
import Foundation
import Vision

private struct OCRPayload: Encodable {
    let text: String
    let lines: [OCRLine]
}

private struct OCRLine: Encodable {
    let text: String
    let rect: OCRRect
}

private struct OCRRect: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 2 else {
    fail("OCR helper requires one image path.")
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("无法读取截图图像。")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
if let supportedLanguages = try? request.supportedRecognitionLanguages() {
    let availableLanguages = preferredLanguages.filter { supportedLanguages.contains($0) }
    request.recognitionLanguages = availableLanguages.isEmpty ? ["en-US"] : availableLanguages
} else {
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
}

do {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])
} catch {
    fail(error.localizedDescription)
}

let imageSize = image.size
private let lines = (request.results ?? [])
    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
    .compactMap { observation -> OCRLine? in
        guard let text = observation.topCandidates(1).first?.string
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let rect = observation.boundingBox
        return OCRLine(
            text: text,
            rect: OCRRect(
                x: rect.minX * imageSize.width,
                y: (1 - rect.maxY) * imageSize.height,
                width: rect.width * imageSize.width,
                height: rect.height * imageSize.height
            )
        )
    }

private let payload = OCRPayload(
    text: lines.map(\.text).joined(separator: "\n"),
    lines: lines
)

do {
    let data = try JSONEncoder().encode(payload)
    FileHandle.standardOutput.write(data)
} catch {
    fail(error.localizedDescription)
}
