import Foundation

@main
struct DoubaoStreamingTransportCheck {
    static func main() async throws {
        try await realDevice48kFrameIsNormalizedToConfigured16k()
        try await requestAndResultMappingStayCredentialSafe()
        try await blockedSocketFailsOpenAtTheBoundedQueue()
        try await malformedAndServerFailuresAreTyped()
        try await connectionFinishAndCancellationFailuresAreIsolated()
        try await firstResultClockStartsWithAudioAndSentenceFinalIsNotStreamFinal()
        try await streamFinalEmitsOrderedTerminalSignalOnce()
        print("DoubaoStreamingTransportCheck passed")
    }

    private static func realDevice48kFrameIsNormalizedToConfigured16k() async throws {
        let socket = FixtureDoubaoSocket()
        let transport = DoubaoStreamingTransport(
            apiKey: "device-48k-sentinel",
            socket: socket,
            requestID: { "device-48k-request" },
            connectID: { "device-48k-connect" }
        )
        try await transport.connect(configuration: configuration)
        try await transport.send(AudioFrame(
            samples: Array(repeating: 0.1, count: 4_800),
            sampleRate: 48_000,
            channelCount: 1,
            startFrame: 0
        ))
        try await waitUntil { await socket.sentCount() == 2 }
        let packet = try await socket.sentData(at: 1)
        precondition(packet.count == 8 + 3_200, "100ms at 16kHz must contain 1600 PCM16 samples")
        await transport.disconnect()
    }

    private static func requestAndResultMappingStayCredentialSafe() async throws {
        let key = "sentinel-secret-never-log"
        let socket = FixtureDoubaoSocket()
        let transport = DoubaoStreamingTransport(
            apiKey: key,
            socket: socket,
            requestID: { "fixture-request" },
            connectID: { "fixture-connect" }
        )
        let events = EventCollector()
        await events.start(stream: transport.messages())

        try await transport.connect(configuration: configuration)
        let request = try await socket.connectedRequest()
        precondition(request.url == URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"))
        precondition(request.value(forHTTPHeaderField: "X-Api-Key") == key)
        precondition(request.value(forHTTPHeaderField: "X-Api-Resource-Id") == "volc.bigasr.sauc.duration")
        precondition(request.value(forHTTPHeaderField: "X-Api-Connect-Id") == "fixture-connect")
        let configurationSendCount = await socket.sentCount()
        precondition(configurationSendCount == 1, "configuration must be sent first")

        try await transport.send(frame(startFrame: 0))
        try await waitUntil { await socket.sentCount() == 2 }
        await socket.emit(serverFrame(text: "今天", sequence: 1, definite: false))
        await socket.emit(serverFrame(text: "今天讨论", sequence: -2, definite: true))
        try await waitUntil { await events.containsFinalized("今天讨论") }

        let captured = await events.values()
        precondition(captured.contains(.connectionChanged(.connected)))
        precondition(captured.contains(.partial(text: "今天", providerSequence: 1)))
        precondition(captured.contains(.finalized(text: "今天讨论", providerSequence: 2)))
        precondition(!String(describing: transport.diagnostics).contains(key))
        precondition(!captured.map { String(describing: $0) }.joined().contains(key))
        await transport.disconnect()
        let normalCloseCount = await socket.closeCount()
        precondition(normalCloseCount == 1)
    }

    private static func blockedSocketFailsOpenAtTheBoundedQueue() async throws {
        let socket = FixtureDoubaoSocket(blockAfterSendCount: 1)
        let transport = DoubaoStreamingTransport(
            apiKey: "overflow-sentinel",
            socket: socket,
            maximumBufferedAudioFrames: 2,
            requestID: { "overflow-request" },
            connectID: { "overflow-connect" }
        )
        let events = EventCollector()
        await events.start(stream: transport.messages())
        try await transport.connect(configuration: configuration)

        for index in 0..<4 {
            try? await transport.send(frame(startFrame: Int64(index * 2)))
        }
        try await waitUntil { await events.containsFailure(code: "audio_queue_overflow") }
        let overflowCloseCount = await socket.closeCount()
        precondition(overflowCloseCount == 1)
        let overflowValues = await events.values()
        precondition(!overflowValues.map { String(describing: $0) }.joined().contains("overflow-sentinel"))
    }

    private static func malformedAndServerFailuresAreTyped() async throws {
        let malformedSocket = FixtureDoubaoSocket()
        let malformed = DoubaoStreamingTransport(
            apiKey: "malformed-sentinel",
            socket: malformedSocket,
            requestID: { "malformed-request" },
            connectID: { "malformed-connect" }
        )
        let malformedEvents = EventCollector()
        await malformedEvents.start(stream: malformed.messages())
        try await malformed.connect(configuration: configuration)
        await malformedSocket.emit(Data([0x11]))
        try await waitUntil { await malformedEvents.containsFailure(code: "malformed_frame") }

        let authSocket = FixtureDoubaoSocket()
        let auth = DoubaoStreamingTransport(
            apiKey: "auth-sentinel",
            socket: authSocket,
            requestID: { "auth-request" },
            connectID: { "auth-connect" }
        )
        let authEvents = EventCollector()
        await authEvents.start(stream: auth.messages())
        try await auth.connect(configuration: configuration)
        await authSocket.emit(serverErrorFrame(code: 401, message: "credential rejected"))
        try await waitUntil { await authEvents.containsFailure(code: "provider_auth") }
        let authValues = await authEvents.values()
        precondition(!authValues.map { String(describing: $0) }.joined().contains("auth-sentinel"))

        let quotaSocket = FixtureDoubaoSocket()
        let quota = DoubaoStreamingTransport(
            apiKey: "quota-sentinel",
            socket: quotaSocket,
            requestID: { "quota-request" },
            connectID: { "quota-connect" }
        )
        let quotaEvents = EventCollector()
        await quotaEvents.start(stream: quota.messages())
        try await quota.connect(configuration: configuration)
        await quotaSocket.emit(serverErrorFrame(code: 429, message: "too many requests"))
        try await waitUntil { await quotaEvents.containsFailure(code: "provider_quota") }
    }

    private static func connectionFinishAndCancellationFailuresAreIsolated() async throws {
        let failedSocket = FixtureDoubaoSocket(connectError: true)
        let failed = DoubaoStreamingTransport(
            apiKey: "connect-sentinel",
            socket: failedSocket,
            connectTimeoutSeconds: 0.1,
            requestID: { "failed-request" },
            connectID: { "failed-connect" }
        )
        let failedEvents = EventCollector()
        await failedEvents.start(stream: failed.messages())
        do {
            try await failed.connect(configuration: configuration)
            preconditionFailure("connect failure must throw")
        } catch {}
        try await waitUntil { await failedEvents.containsFailure(code: "connect_failed") }
        let failedCloseCount = await failedSocket.closeCount()
        precondition(failedCloseCount == 1)

        let finishSocket = FixtureDoubaoSocket()
        let finish = DoubaoStreamingTransport(
            apiKey: "finish-sentinel",
            socket: finishSocket,
            firstResultTimeoutSeconds: 1,
            finishTimeoutSeconds: 0.03,
            requestID: { "finish-request" },
            connectID: { "finish-connect" }
        )
        let finishEvents = EventCollector()
        await finishEvents.start(stream: finish.messages())
        try await finish.connect(configuration: configuration)
        do {
            try await finish.finishInput()
            preconditionFailure("finish timeout must throw")
        } catch {}
        try await waitUntil { await finishEvents.containsFailure(code: "finish_timeout") }

        let cancelledSocket = FixtureDoubaoSocket()
        let cancelled = DoubaoStreamingTransport(
            apiKey: "cancel-sentinel",
            socket: cancelledSocket,
            requestID: { "cancel-request" },
            connectID: { "cancel-connect" }
        )
        let cancelledEvents = EventCollector()
        await cancelledEvents.start(stream: cancelled.messages())
        try await cancelled.connect(configuration: configuration)
        try await waitUntil { await cancelledEvents.values().contains(.connectionChanged(.connected)) }
        await cancelled.disconnect()
        await cancelledSocket.emit(serverFrame(text: "晚到不能出现", sequence: 99, definite: true))
        try await Task.sleep(for: .milliseconds(20))
        let afterLate = await cancelledEvents.values()
        precondition(!afterLate.map { String(describing: $0) }.joined().contains("晚到"))
    }

    private static func firstResultClockStartsWithAudioAndSentenceFinalIsNotStreamFinal() async throws {
        let silentSocket = FixtureDoubaoSocket()
        let silent = DoubaoStreamingTransport(
            apiKey: "silence-sentinel",
            socket: silentSocket,
            firstResultTimeoutSeconds: 0.02,
            requestID: { "silence-request" },
            connectID: { "silence-connect" }
        )
        let silentEvents = EventCollector()
        await silentEvents.start(stream: silent.messages())
        try await silent.connect(configuration: configuration)
        try await Task.sleep(for: .milliseconds(40))
        let failedWhileSilent = await silentEvents.containsFailure(code: "first_result_timeout")
        precondition(!failedWhileSilent)
        try await silent.send(frame(startFrame: 0))
        try await waitUntil { await silentEvents.containsFailure(code: "first_result_timeout") }

        let sentenceSocket = FixtureDoubaoSocket()
        let sentence = DoubaoStreamingTransport(
            apiKey: "sentence-sentinel",
            socket: sentenceSocket,
            firstResultTimeoutSeconds: 1,
            finishTimeoutSeconds: 0.03,
            requestID: { "sentence-request" },
            connectID: { "sentence-connect" }
        )
        let sentenceEvents = EventCollector()
        await sentenceEvents.start(stream: sentence.messages())
        try await sentence.connect(configuration: configuration)
        try await sentence.send(frame(startFrame: 0))
        await sentenceSocket.emit(serverFrame(text: "一句完成", sequence: 1, definite: true))
        try await waitUntil { await sentenceEvents.containsFinalized("一句完成") }
        let sentenceValues = await sentenceEvents.values()
        precondition(!sentenceValues.contains(.completed))
        do {
            try await sentence.finishInput()
            preconditionFailure("sentence definite must not satisfy stream final")
        } catch {}
        try await waitUntil { await sentenceEvents.containsFailure(code: "finish_timeout") }
    }

    private static func streamFinalEmitsOrderedTerminalSignalOnce() async throws {
        let socket = FixtureDoubaoSocket()
        let transport = DoubaoStreamingTransport(
            apiKey: "stream-final-sentinel",
            socket: socket,
            firstResultTimeoutSeconds: 1,
            finishTimeoutSeconds: 1,
            requestID: { "stream-final-request" },
            connectID: { "stream-final-connect" }
        )
        let events = EventCollector()
        await events.start(stream: transport.messages())
        try await transport.connect(configuration: configuration)
        try await transport.send(frame(startFrame: 0))

        let finishTask = Task { try await transport.finishInput() }
        try await waitUntil { await socket.sentCount() == 3 }
        await socket.emit(serverFrame(text: "整流完成", sequence: -1, definite: true))
        try await finishTask.value
        try await waitUntil { await events.values().contains(.completed) }
        await socket.emit(serverFrame(text: "晚到不能出现", sequence: -2, definite: true))
        try await Task.sleep(for: .milliseconds(20))

        let values = await events.values()
        let finalizedIndex = values.firstIndex(of: .finalized(text: "整流完成", providerSequence: 1))
        let completedIndex = values.firstIndex(of: .completed)
        precondition(finalizedIndex != nil && completedIndex != nil && finalizedIndex! < completedIndex!)
        precondition(values.filter { $0 == .completed }.count == 1)
        precondition(!values.map { String(describing: $0) }.joined().contains("晚到"))
        precondition(!values.map { String(describing: $0) }.joined().contains("stream-final-sentinel"))
        await transport.disconnect()
    }

    private static let configuration = OnlineProviderConfiguration(
        sampleRate: 16_000,
        channelCount: 1,
        languageHint: "zh",
        connectionTimeoutSeconds: 5
    )

    private static func frame(startFrame: Int64) -> AudioFrame {
        AudioFrame(samples: [0.1, -0.1], sampleRate: 16_000, channelCount: 1, startFrame: startFrame)
    }

    private static func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("timed out")
    }

    private static func serverFrame(text: String, sequence: Int32, definite: Bool) -> Data {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "reqid": "fixture-request",
            "result": [
                "text": text,
                "utterances": [["text": text, "start_time": 0, "end_time": 500, "definite": definite]],
            ],
        ])
        var data = Data([0x11, sequence < 0 ? 0x93 : 0x91, 0x10, 0x00])
        append(UInt32(bitPattern: sequence), to: &data)
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private static func serverErrorFrame(code: UInt32, message: String) -> Data {
        let payload = try! JSONSerialization.data(withJSONObject: ["message": message])
        var data = Data([0x11, 0xF0, 0x10, 0x00])
        append(code, to: &data)
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ])
    }
}

private actor FixtureDoubaoSocket: DoubaoWebSocketSession {
    private var request: URLRequest?
    private var sent: [Data] = []
    private var closes = 0
    private let blockAfterSendCount: Int?
    private let connectError: Bool
    private let incoming: AsyncStream<Data>
    private let incomingContinuation: AsyncStream<Data>.Continuation

    init(blockAfterSendCount: Int? = nil, connectError: Bool = false) {
        self.blockAfterSendCount = blockAfterSendCount
        self.connectError = connectError
        var captured: AsyncStream<Data>.Continuation!
        incoming = AsyncStream { captured = $0 }
        incomingContinuation = captured
    }

    func connect(request: URLRequest) async throws {
        if connectError { throw FixtureError.connectFailed }
        self.request = request
    }
    func send(_ data: Data) async throws {
        if let blockAfterSendCount, sent.count >= blockAfterSendCount {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        sent.append(data)
    }
    func receive() async throws -> Data {
        for await data in incoming { return data }
        throw FixtureError.closed
    }
    func close() async { closes += 1; incomingContinuation.finish() }
    func emit(_ data: Data) { incomingContinuation.yield(data) }
    func connectedRequest() throws -> URLRequest {
        guard let request else { throw FixtureError.missingRequest }
        return request
    }
    func sentCount() -> Int { sent.count }
    func sentData(at index: Int) throws -> Data {
        guard sent.indices.contains(index) else { throw FixtureError.missingSend }
        return sent[index]
    }
    func closeCount() -> Int { closes }

    enum FixtureError: Error { case closed, missingRequest, missingSend, connectFailed }
}

private actor EventCollector {
    private var events: [OnlineProviderMessage] = []
    private var task: Task<Void, Never>?

    func start(stream: AsyncStream<OnlineProviderMessage>) {
        guard task == nil else { return }
        task = Task {
            for await event in stream { self.record(event) }
        }
    }

    private func record(_ event: OnlineProviderMessage) { events.append(event) }
    func values() -> [OnlineProviderMessage] { events }
    func containsFinalized(_ text: String) -> Bool {
        events.contains { if case .finalized(let value, _) = $0 { value == text } else { false } }
    }
    func containsFailure(code: String) -> Bool {
        events.contains { if case .failed(let value, _, _) = $0 { value == code } else { false } }
    }
}
