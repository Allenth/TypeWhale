import Foundation
import CryptoKit

enum ReaderClipboardMarker {
    static let pasteboardTypeRawValue = "com.waykingah.reader.source"

    private struct Payload: Encodable {
        let version = 1
        let kind = "typewhale-generated"
        let producerBundleIdentifier: String
        let createdAt: Date
        let restoredClipboardTextSHA256: String?
    }

    static func encode(
        producerBundleIdentifier: String,
        restoredClipboardText: String? = nil,
        createdAt: Date = Date()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            Payload(
                producerBundleIdentifier: producerBundleIdentifier,
                createdAt: createdAt,
                restoredClipboardTextSHA256: restoredClipboardText.map(textSHA256)
            )
        )
    }

    private static func textSHA256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
