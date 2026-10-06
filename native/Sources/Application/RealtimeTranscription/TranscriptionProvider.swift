import Foundation

struct AudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channelCount: Int
    let startFrame: Int64
}

struct TranscriptionProviderCapabilities: Equatable, Sendable {
    let supportsRealtimePCM: Bool
    let supportsPartialResults: Bool
    let supportsServerFinalization: Bool
    let maximumConcurrentSessions: Int
}

protocol TranscriptionProvider: Sendable {
    var id: String { get }
    var capabilities: TranscriptionProviderCapabilities { get }

    func start(
        sessionID: TranscriptionSessionID,
        providerEpoch: Int
    ) async throws
    func append(_ frame: AudioFrame) async throws
    func finish() async throws
    func cancel() async
    func events() -> AsyncStream<TranscriptionEvent>
}

enum TranscriptionSessionError: Error, Equatable {
    case notStarted
    case terminal
}
