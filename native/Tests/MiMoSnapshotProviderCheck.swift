import Foundation

@main
struct MiMoSnapshotProviderCheck {
    static func main() async throws {
        try await realDevice48kFramesNormalizeBeforeScheduling()
        try await snapshotScheduleStartsAtTwoThenRepeatsEveryFourSeconds()
        try await laterSnapshotReplayDoesNotEmitShorterPartials()
        try await completedSnapshotRollbackDoesNotReplacePublishedPreview()
        try await slowTwoMinuteStreamStaysLatestOnlyAndBounded()
        try await tenMinuteFastStreamStaysBoundedAndCleansTerminalState()
        try await failureMatrixCleansFilesAndSanitizesEvents()
        try await finishDuringActiveRequestDrainsLatestSnapshot()
        try await cancelRejectsLateCompletion()
        print("MiMoSnapshotProviderCheck passed")
    }

    private static func completedSnapshotRollbackDoesNotReplacePublishedPreview() async throws {
        let root = temporaryRoot("completed-rollback")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(
            apiKey: "completed-rollback-sentinel",
            http: http,
            temporaryDirectory: root
        )
        let events = TranscriptionEventCollector()
        await events.start(provider.events())
        try await provider.start(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1
        )

        let accepted = String(repeating: "甲", count: 11)
        let extended = accepted + String(repeating: "乙", count: 11)
        let rollback = String(repeating: "丙", count: 11)
        let laterExtension = extended + "丁"

        for index in 0..<20 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: [accepted])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 1 }

        for index in 20..<60 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: [extended])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 2 }

        for index in 60..<100 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: [rollback])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 3 }

        for index in 100..<140 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: [laterExtension])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 4 }
        try await Task.sleep(for: .milliseconds(20))

        let partials = await events.values().compactMap { event -> String? in
            guard case .partial(_, _, _, let text) = event else { return nil }
            return text
        }
        precondition(!partials.contains(rollback))
        precondition(partials.contains(laterExtension) || partials.contains("丁"))

        await provider.cancel()
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func laterSnapshotReplayDoesNotEmitShorterPartials() async throws {
        let root = temporaryRoot("partial-replay")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(
            apiKey: "partial-replay-sentinel",
            http: http,
            temporaryDirectory: root
        )
        let events = TranscriptionEventCollector()
        await events.start(provider.events())
        try await provider.start(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1
        )

        for index in 0..<20 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: ["在线模型"])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 1 }

        for index in 20..<60 { try await provider.append(frame(index: index)) }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(chunks: ["在", "线模型", "支持"])
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 2 }
        try await Task.sleep(for: .milliseconds(20))

        let partials = await events.values().compactMap { event -> String? in
            guard case .partial(_, _, _, let text) = event else { return nil }
            return text
        }
        precondition(!partials.contains("在"))
        precondition(partials.contains("在线模型支持"))

        await provider.cancel()
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func realDevice48kFramesNormalizeBeforeScheduling() async throws {
        let root = temporaryRoot("device-48k")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(
            apiKey: "device-48k-sentinel",
            http: http,
            temporaryDirectory: root
        )
        try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 1)

        for index in 0..<20 {
            try await provider.append(AudioFrame(
                samples: Array(repeating: Float(index % 5) / 10, count: 4_800),
                sampleRate: 48_000,
                channelCount: 1,
                startFrame: Int64(index * 4_800)
            ))
        }

        try await waitUntil { await http.blockedRequestCount() == 1 }
        let diagnostics = await provider.diagnosticsSnapshot()
        precondition(diagnostics.maximumBufferedSamples <= 32_000)
        precondition(diagnostics.maximumConcurrentRequests == 1)
        await provider.cancel()
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func snapshotScheduleStartsAtTwoThenRepeatsEveryFourSeconds() async throws {
        let root = temporaryRoot("schedule")
        let stale = root.appendingPathComponent("stale-from-interrupted-process.wav")
        try Data([0x01]).write(to: stale)
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(apiKey: "schedule-sentinel", http: http, temporaryDirectory: root)
        try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 1)
        precondition(!FileManager.default.fileExists(atPath: stale.path))

        for index in 0..<19 { try await provider.append(frame(index: index)) }
        let beforeFirst = await provider.diagnosticsSnapshot()
        precondition(beforeFirst.activeRequests == 0)
        try await provider.append(frame(index: 19))
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(text: "今天")
        try await waitUntil { (await provider.diagnosticsSnapshot()).completedRequests == 1 }

        for index in 20..<59 { try await provider.append(frame(index: index)) }
        let beforeSecond = await provider.diagnosticsSnapshot()
        precondition(beforeSecond.activeRequests == 0)
        try await provider.append(frame(index: 59))
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await provider.cancel()
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func slowTwoMinuteStreamStaysLatestOnlyAndBounded() async throws {
        let root = temporaryRoot("slow")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(apiKey: "slow-sentinel", http: http, temporaryDirectory: root)
        try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 1)

        for index in 0..<1_200 {
            try await provider.append(frame(index: index))
        }
        try await waitUntil { (await provider.diagnosticsSnapshot()).activeRequests == 1 }
        let diagnostics = await provider.diagnosticsSnapshot()
        precondition(diagnostics.maximumConcurrentRequests == 1)
        precondition(diagnostics.maximumPendingSnapshots == 1)
        precondition(diagnostics.maximumBufferedSamples <= 192_000)
        precondition(diagnostics.maximumRequestBytes <= 9_000_000)
        precondition(diagnostics.currentBufferedSamples <= 192_000)
        precondition(diagnostics.pendingSnapshots == 1)

        await provider.cancel()
        try await assertTerminalResourcesAreZero(provider, root: root)
        let fixtureMaximum = await http.maximumConcurrentRequests()
        precondition(fixtureMaximum == 1)
    }

    private static func tenMinuteFastStreamStaysBoundedAndCleansTerminalState() async throws {
        let root = temporaryRoot("fast")
        let http = FixtureMiMoHTTP(mode: .fast)
        let provider = MiMoSnapshotProvider(apiKey: "fast-sentinel", http: http, temporaryDirectory: root)
        let events = TranscriptionEventCollector()
        await events.start(provider.events())
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        try await provider.start(sessionID: sessionID, providerEpoch: 3)

        for index in 0..<6_000 {
            try await provider.append(frame(index: index))
            if index.isMultiple(of: 50) { await Task.yield() }
        }
        try await provider.finish()
        try await waitUntil { await events.containsCompleted() }

        let diagnostics = await provider.diagnosticsSnapshot()
        precondition(diagnostics.maximumConcurrentRequests == 1)
        precondition(diagnostics.maximumPendingSnapshots <= 1)
        precondition(diagnostics.maximumBufferedSamples <= 192_000)
        precondition(diagnostics.maximumRequestBytes <= 9_000_000)
        precondition(diagnostics.completedRequests > 0)
        var reducer = TranscriptReducer(sessionID: sessionID, providerEpoch: 3)
        for event in await events.values() { _ = reducer.apply(event) }
        precondition(reducer.state.lifecycle == .completed)
        precondition(reducer.state.volatileText.isEmpty)
        precondition(reducer.state.confirmedText == "今天讨论在线模型")
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func failureMatrixCleansFilesAndSanitizesEvents() async throws {
        let cases: [(String, FixtureMiMoHTTP.Mode, any MiMoASRRequestBuilding)] = [
            ("401", .status(401), MiMoASRRequestBuilder(apiKey: "401-sentinel")),
            ("429", .status(429), MiMoASRRequestBuilder(apiKey: "429-sentinel")),
            ("500", .status(500), MiMoASRRequestBuilder(apiKey: "500-sentinel")),
            ("timeout", .timeout, MiMoASRRequestBuilder(apiKey: "timeout-sentinel")),
            ("malformed", .malformed, MiMoASRRequestBuilder(apiKey: "malformed-sentinel")),
            ("too-large", .fast, RejectingMiMoRequestBuilder()),
        ]

        for (name, mode, builder) in cases {
            let root = temporaryRoot(name)
            let http = FixtureMiMoHTTP(mode: mode)
            let provider = MiMoSnapshotProvider(
                apiKey: "\(name)-sentinel",
                http: http,
                requestBuilder: builder,
                temporaryDirectory: root
            )
            let events = TranscriptionEventCollector()
            await events.start(provider.events())
            try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 5)
            for index in 0..<20 { try await provider.append(frame(index: index)) }
            try await waitUntil { await events.containsFailure() }
            let rendered = await events.values().map { String(describing: $0) }.joined()
            precondition(!rendered.contains("\(name)-sentinel"))
            await provider.cancel()
            try await assertTerminalResourcesAreZero(provider, root: root)
        }
    }

    private static func cancelRejectsLateCompletion() async throws {
        let root = temporaryRoot("late")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(apiKey: "late-sentinel", http: http, temporaryDirectory: root)
        let events = TranscriptionEventCollector()
        await events.start(provider.events())
        try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 7)
        for index in 0..<20 { try await provider.append(frame(index: index)) }
        try await waitUntil { (await provider.diagnosticsSnapshot()).activeRequests == 1 }
        await provider.cancel()
        try await waitUntil { await events.containsCancelled() }
        await http.emitLateSuccess()
        try await Task.sleep(for: .milliseconds(20))
        let afterLate = await events.values()
        precondition(!afterLate.map { String(describing: $0) }.joined().contains("晚到"))
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func finishDuringActiveRequestDrainsLatestSnapshot() async throws {
        let root = temporaryRoot("finish-active")
        let http = FixtureMiMoHTTP(mode: .blocked)
        let provider = MiMoSnapshotProvider(apiKey: "finish-active-sentinel", http: http, temporaryDirectory: root)
        let events = TranscriptionEventCollector()
        await events.start(provider.events())
        try await provider.start(sessionID: TranscriptionSessionID(rawValue: UUID()), providerEpoch: 9)
        for index in 0..<20 { try await provider.append(frame(index: index)) }
        try await waitUntil { (await provider.diagnosticsSnapshot()).activeRequests == 1 }

        let finishTask = Task { try await provider.finish() }
        try await waitUntil { (await provider.diagnosticsSnapshot()).pendingSnapshots == 1 }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(text: "今天")
        try await waitUntil {
            let value = await provider.diagnosticsSnapshot()
            return value.completedRequests == 1 && value.activeRequests == 1
        }
        try await waitUntil { await http.blockedRequestCount() == 1 }
        await http.releaseOneSuccess(text: "今天讨论")
        try await finishTask.value
        try await waitUntil { await events.containsCompleted() }
        try await assertTerminalResourcesAreZero(provider, root: root)
    }

    private static func frame(index: Int) -> AudioFrame {
        AudioFrame(
            samples: Array(repeating: Float(index % 5) / 10, count: 1_600),
            sampleRate: 16_000,
            channelCount: 1,
            startFrame: Int64(index * 1_600)
        )
    }

    private static func temporaryRoot(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeWhaleMiMoTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func assertTerminalResourcesAreZero(
        _ provider: MiMoSnapshotProvider,
        root: URL
    ) async throws {
        let diagnostics = await provider.diagnosticsSnapshot()
        precondition(diagnostics.currentBufferedSamples == 0)
        precondition(diagnostics.pendingSnapshots == 0)
        precondition(diagnostics.activeRequests == 0)
        precondition(diagnostics.temporaryFileCount == 0)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(files.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    private static func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("timed out")
    }
}

private struct RejectingMiMoRequestBuilder: MiMoASRRequestBuilding {
    func makeRequest(wavData: Data, language: MiMoASRLanguage) throws -> URLRequest {
        throw MiMoASRProtocolError.audioTooLarge
    }
}

private actor FixtureMiMoHTTP: MiMoHTTPStreaming {
    enum Mode { case fast, blocked, status(Int), timeout, malformed }
    private let mode: Mode
    private var active = 0
    private var maximumActive = 0
    private var blockedContinuations: [AsyncThrowingStream<Data, Error>.Continuation] = []

    init(mode: Mode) { self.mode = mode }

    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        active += 1
        maximumActive = max(maximumActive, active)
        switch mode {
        case .status(let code):
            active -= 1
            throw MiMoHTTPError.status(code)
        case .timeout:
            active -= 1
            throw URLError(.timedOut)
        case .malformed:
            active -= 1
            return AsyncThrowingStream { continuation in
                continuation.yield(Data("data: {bad-json}\n\n".utf8))
                continuation.finish()
            }
        case .fast:
            active -= 1
            return AsyncThrowingStream { continuation in
                continuation.yield(Data("data: {\"choices\":[{\"delta\":{\"content\":\"今天讨论在线模型\"}}]}\n\n".utf8))
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
        case .blocked:
            return AsyncThrowingStream { continuation in
                blockedContinuations.append(continuation)
            }
        }
    }

    func cancel() async {
        let continuations = blockedContinuations
        blockedContinuations.removeAll()
        active = max(0, active - continuations.count)
        continuations.forEach { $0.finish(throwing: CancellationError()) }
    }

    func emitLateSuccess() {
        let continuations = blockedContinuations
        blockedContinuations.removeAll()
        active = max(0, active - continuations.count)
        continuations.forEach {
            $0.yield(Data("data: {\"choices\":[{\"delta\":{\"content\":\"晚到\"}}]}\n\ndata: [DONE]\n\n".utf8))
            $0.finish()
        }
    }

    func releaseOneSuccess(text: String) {
        releaseOneSuccess(chunks: [text])
    }

    func releaseOneSuccess(chunks: [String]) {
        guard !blockedContinuations.isEmpty else { return }
        let continuation = blockedContinuations.removeFirst()
        active = max(0, active - 1)
        for chunk in chunks {
            continuation.yield(Data(
                "data: {\"choices\":[{\"delta\":{\"content\":\"\(chunk)\"}}]}\n\n".utf8
            ))
        }
        continuation.yield(Data("data: [DONE]\n\n".utf8))
        continuation.finish()
    }

    func maximumConcurrentRequests() -> Int { maximumActive }
    func blockedRequestCount() -> Int { blockedContinuations.count }
}

private actor TranscriptionEventCollector {
    private var events: [TranscriptionEvent] = []
    private var task: Task<Void, Never>?

    func start(_ stream: AsyncStream<TranscriptionEvent>) {
        guard task == nil else { return }
        task = Task { for await event in stream { self.events.append(event) } }
    }
    func values() -> [TranscriptionEvent] { events }
    func containsCompleted() -> Bool {
        events.contains { if case .completed = $0 { true } else { false } }
    }
    func containsFailure() -> Bool {
        events.contains { if case .failed = $0 { true } else { false } }
    }
    func containsCancelled() -> Bool {
        events.contains { if case .cancelled = $0 { true } else { false } }
    }
}
