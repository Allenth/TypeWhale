import Foundation

@main
struct FakeStreamingProviderCheck {
    static func main() async throws {
        try await scriptedStreamUsesTheExistingSessionContract()
        try await failureInjectionIsDeterministic()
        onlineTransportPortStaysVendorNeutral()
        print("FakeStreamingProviderCheck passed")
    }

    private static func onlineTransportPortStaysVendorNeutral() {
        let configuration = OnlineProviderConfiguration(
            sampleRate: 16_000,
            channelCount: 1,
            languageHint: "zh",
            connectionTimeoutSeconds: 8
        )
        precondition(configuration.sampleRate == 16_000)
        let transport: any OnlineStreamingTransport = TestOnlineStreamingTransport()
        _ = transport.messages()
    }

    private static func scriptedStreamUsesTheExistingSessionContract() async throws {
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let first = FakeStreamingProvider(
            id: "fake-first",
            script: [
                .init(emission: .partial(segmentID: "s0", revision: 1, text: "今")),
                .init(emission: .partial(segmentID: "s0", revision: 2, text: "今天")),
                .init(emission: .partial(segmentID: "s0", revision: 3, text: "今天讨论")),
                .init(emission: .finalized(TranscriptSegment(
                    id: "s0",
                    text: "今天讨论",
                    audioRange: TranscriptionAudioRange(start: 0, end: 1)
                ))),
                .init(emission: .partial(segmentID: "s1", revision: 1, text: "在线模型")),
                .init(emission: .connectionChanged(.reconnecting(attempt: 1))),
                .init(
                    emission: .partial(segmentID: "stale", revision: 1, text: "旧代次不能出现"),
                    providerEpochOffset: -1
                ),
            ],
            defaultDelayNanoseconds: 15_000_000
        )
        let session = TranscriptionSession(sessionID: sessionID, provider: first)
        try await session.start()
        try await session.append(AudioFrame(
            samples: [0.1, -0.1],
            sampleRate: 16_000,
            channelCount: 1,
            startFrame: 0
        ))

        _ = await waitForState(session) { $0.volatileText == "今" }
        _ = await waitForState(session) { $0.volatileText == "今天" }
        _ = await waitForState(session) { $0.volatileText == "今天讨论" }
        _ = await waitForState(session) { $0.confirmedText == "今天讨论" }
        _ = await waitForState(session) { $0.volatileText == "在线模型" }
        let reconnecting = await waitForState(session) {
            $0.connectionState == .reconnecting(attempt: 1)
        }
        try await Task.sleep(nanoseconds: 25_000_000)
        let afterStale = await session.currentState()
        precondition(afterStale.confirmedText == reconnecting.confirmedText)
        precondition(afterStale.volatileText == "在线模型")
        precondition(!afterStale.volatileText.contains("旧代次"))
        precondition(first.receivedFrameCount == 1)

        let second = FakeStreamingProvider(
            id: "fake-second",
            script: [
                .init(emission: .partial(segmentID: "s2", revision: 1, text: "在线模型支持流式输出")),
                .init(emission: .completed),
            ],
            defaultDelayNanoseconds: 15_000_000
        )
        try await session.switchProvider(to: second)
        _ = await waitForState(session) { $0.volatileText == "在线模型支持流式输出" }
        let completed = await waitForState(session) { $0.lifecycle == .completed }
        precondition(completed.confirmedText == "今天讨论")
        precondition(completed.providerEpoch == 2)
    }

    private static func failureInjectionIsDeterministic() async throws {
        let provider = FakeStreamingProvider(
            id: "fake-failure",
            script: [],
            failureInjection: .append(afterAcceptedFrameCount: 0)
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        try await session.start()
        do {
            try await session.append(AudioFrame(
                samples: [0],
                sampleRate: 16_000,
                channelCount: 1,
                startFrame: 0
            ))
            preconditionFailure("append failure injection must throw")
        } catch let error as FakeStreamingProviderError {
            precondition(error == .injectedAppendFailure)
        }
    }

    private static func waitForState(
        _ session: TranscriptionSession,
        matching predicate: (TranscriptState) -> Bool
    ) async -> TranscriptState {
        for _ in 0..<2_000 {
            let state = await session.currentState()
            if predicate(state) { return state }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("timed out waiting for scripted streaming state")
    }
}

private final class TestOnlineStreamingTransport: OnlineStreamingTransport, @unchecked Sendable {
    func connect(configuration: OnlineProviderConfiguration) async throws {}
    func send(_ frame: AudioFrame) async throws {}
    func finishInput() async throws {}
    func disconnect() async {}
    func messages() -> AsyncStream<OnlineProviderMessage> {
        AsyncStream { $0.finish() }
    }
}
