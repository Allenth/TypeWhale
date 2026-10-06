import Foundation

@main
struct OnlineASRProviderFactoryCheck {
    static func main() {
        let credentials = FixtureCredentialStore()
        let recorder = BuilderRecorder()
        let factory = OnlineASRProviderFactory(
            credentials: credentials,
            doubaoBuilder: { key in recorder.make(id: "doubao", key: key) },
            mimoBuilder: { key in recorder.make(id: "mimo", key: key) }
        )

        guard case .disabled = factory.make(selection: .off) else { preconditionFailure() }
        guard case .unavailable(.missingCredential(.doubaoAPIKey)) = factory.make(selection: .doubao) else { preconditionFailure() }
        guard case .unavailable(.missingCredential(.mimoAPIKey)) = factory.make(selection: .mimoV25) else { preconditionFailure() }

        credentials.values[.doubaoAPIKey] = "doubao-sentinel"
        guard case .ready(let doubao) = factory.make(selection: .doubao) else { preconditionFailure() }
        precondition(doubao.id == "doubao")
        precondition(recorder.calls == ["doubao:doubao-sentinel"])

        credentials.values[.mimoAPIKey] = "mimo-sentinel"
        guard case .ready(let mimo) = factory.make(selection: .mimoV25) else { preconditionFailure() }
        precondition(mimo.id == "mimo")
        precondition(recorder.calls == ["doubao:doubao-sentinel", "mimo:mimo-sentinel"])
        print("OnlineASRProviderFactoryCheck passed")
    }
}

private final class FixtureCredentialStore: OnlineASRCredentialStoring, @unchecked Sendable {
    var values: [OnlineASRCredentialKind: String] = [:]
    func load(_ kind: OnlineASRCredentialKind) -> String? { values[kind] }
    func has(_ kind: OnlineASRCredentialKind) -> Bool { load(kind) != nil }
    func save(_ value: String, for kind: OnlineASRCredentialKind) throws { values[kind] = value }
    func delete(_ kind: OnlineASRCredentialKind) { values.removeValue(forKey: kind) }
}

private final class BuilderRecorder: @unchecked Sendable {
    var calls: [String] = []
    func make(id: String, key: String) -> any TranscriptionProvider {
        calls.append("\(id):\(key)")
        return NoopProvider(id: id)
    }
}

private struct NoopProvider: TranscriptionProvider {
    let id: String
    let capabilities = TranscriptionProviderCapabilities(supportsRealtimePCM: true, supportsPartialResults: true, supportsServerFinalization: true, maximumConcurrentSessions: 1)
    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {}
    func append(_ frame: AudioFrame) async throws {}
    func finish() async throws {}
    func cancel() async {}
    func events() -> AsyncStream<TranscriptionEvent> { AsyncStream { $0.finish() } }
}
