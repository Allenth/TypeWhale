import Foundation

@main
struct ReaderClipboardMarkerCheck {
    static func main() throws {
        let createdAt = Date(timeIntervalSince1970: 1_785_081_600)
        let data = try ReaderClipboardMarker.encode(
            producerBundleIdentifier: "com.waykingah.typewhale.pro",
            restoredClipboardText: "用户原有剪贴板",
            createdAt: createdAt
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        precondition(ReaderClipboardMarker.pasteboardTypeRawValue == "com.waykingah.reader.source")
        precondition(object?["version"] as? Int == 1)
        precondition(object?["kind"] as? String == "typewhale-generated")
        precondition(
            object?["producerBundleIdentifier"] as? String
                == "com.waykingah.typewhale.pro"
        )
        precondition(object?["restoredClipboardTextSHA256"] as? String ==
            "a1542a6b47c710d61216e9788d881dd9417c6315038dfcedc5f03c5b7938941e")
        precondition(!String(decoding: data, as: UTF8.self).contains("用户原有剪贴板"))

        print("ReaderClipboardMarkerCheck passed")
    }
}
