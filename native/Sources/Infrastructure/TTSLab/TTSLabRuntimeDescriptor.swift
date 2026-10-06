import Foundation

struct TTSLabRuntimeDescriptor: Equatable {
    let adapterID: String
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let fingerprint: String
}
