import Foundation

struct MiMoSnapshotProviderDiagnostics: Sendable, Equatable {
    let currentBufferedSamples: Int
    let pendingSnapshots: Int
    let activeRequests: Int
    let temporaryFileCount: Int
    let completedRequests: Int
    let maximumBufferedSamples: Int
    let maximumPendingSnapshots: Int
    let maximumConcurrentRequests: Int
    let maximumRequestBytes: Int
}

enum MiMoSnapshotProviderError: Error, Sendable, Equatable {
    case invalidAudioFrame
    case notStarted
    case terminal
}

actor MiMoSnapshotProvider: TranscriptionProvider {
    nonisolated let id = "mimo-v2.5-asr"
    nonisolated let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: false,
        supportsPartialResults: true,
        supportsServerFinalization: true,
        maximumConcurrentSessions: 1
    )
    nonisolated let eventStream: AsyncStream<TranscriptionEvent>

    private let http: any MiMoHTTPStreaming
    private let requestBuilder: any MiMoASRRequestBuilding
    private let temporaryDirectory: URL
    private let language: MiMoASRLanguage
    private let eventContinuation: AsyncStream<TranscriptionEvent>.Continuation
    private let sampleRate = 16_000
    private let firstSnapshotFrames = 32_000
    private let snapshotIntervalFrames = 64_000
    private let maximumRollingFrames = 192_000

    private var sessionID: TranscriptionSessionID?
    private var providerEpoch = 0
    private var eventSequence: UInt64 = 0
    private var partialRevision = 0
    private var finalizedIndex = 0
    private var rollingSamples: [Float] = []
    private var rollingStartFrame: Int64 = 0
    private var latestEndFrame: Int64 = 0
    private var nextSnapshotAtFrame: Int64 = 32_000
    private var activeTask: Task<Void, Never>?
    private var pendingSnapshot: Snapshot?
    private var terminal = false
    private var finishing = false
    private var reconciler = SenseVoiceBoundaryReconciler(strategy: .lexicalOverlap)
    private var emittedConfirmedText = ""
    private var projectedText = ""
    private var requestPartialProjection = MiMoRequestPartialProjection()
    private var lastSnapshotRange = TranscriptionAudioRange(start: 0, end: 0)
    private var inputResampler = StreamingMonoPCMResampler()

    private var activeRequests = 0
    private var temporaryFileCount = 0
    private var completedRequests = 0
    private var maximumBufferedSamples = 0
    private var maximumPendingSnapshots = 0
    private var maximumConcurrentRequests = 0
    private var maximumRequestBytes = 0

    init(
        apiKey: String,
        http: any MiMoHTTPStreaming = MiMoHTTPTransport(),
        requestBuilder: (any MiMoASRRequestBuilding)? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeWhaleMiMoASR", isDirectory: true),
        language: MiMoASRLanguage = .auto
    ) {
        self.http = http
        self.requestBuilder = requestBuilder ?? MiMoASRRequestBuilder(apiKey: apiKey)
        self.temporaryDirectory = temporaryDirectory
        self.language = language
        var captured: AsyncStream<TranscriptionEvent>.Continuation!
        eventStream = AsyncStream { captured = $0 }
        eventContinuation = captured
    }

    nonisolated func events() -> AsyncStream<TranscriptionEvent> { eventStream }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        guard self.sessionID == nil else { return }
        guard !terminal else { throw MiMoSnapshotProviderError.terminal }
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) {
            for staleFile in staleFiles { try? FileManager.default.removeItem(at: staleFile) }
        }
        self.sessionID = sessionID
        self.providerEpoch = providerEpoch
        emit(.connectionChanged(metadata(), .connected))
    }

    func append(_ frame: AudioFrame) async throws {
        guard sessionID != nil else { throw MiMoSnapshotProviderError.notStarted }
        guard !terminal, !finishing else { throw MiMoSnapshotProviderError.terminal }
        guard frame.sampleRate > 0,
              frame.channelCount == 1,
              !frame.samples.isEmpty else {
            throw MiMoSnapshotProviderError.invalidAudioFrame
        }
        let normalizedFrame: AudioFrame?
        do {
            normalizedFrame = try inputResampler.append(frame)
        } catch {
            throw MiMoSnapshotProviderError.invalidAudioFrame
        }
        guard let normalizedFrame else { return }

        if rollingSamples.isEmpty { rollingStartFrame = normalizedFrame.startFrame }
        rollingSamples.append(contentsOf: normalizedFrame.samples)
        latestEndFrame = max(
            latestEndFrame,
            normalizedFrame.startFrame + Int64(normalizedFrame.samples.count)
        )
        if rollingSamples.count > maximumRollingFrames {
            let overflow = rollingSamples.count - maximumRollingFrames
            rollingSamples.removeFirst(overflow)
            rollingStartFrame = latestEndFrame - Int64(rollingSamples.count)
        }
        maximumBufferedSamples = max(maximumBufferedSamples, rollingSamples.count)

        guard latestEndFrame >= nextSnapshotAtFrame else { return }
        while nextSnapshotAtFrame <= latestEndFrame {
            nextSnapshotAtFrame += Int64(snapshotIntervalFrames)
        }
        schedule(snapshot())
    }

    func finish() async throws {
        guard sessionID != nil else { throw MiMoSnapshotProviderError.notStarted }
        guard !terminal else { return }
        finishing = true
        if !rollingSamples.isEmpty { schedule(snapshot()) }
        if activeTask == nil, pendingSnapshot == nil {
            completeSuccessfully()
        }
        while !terminal {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func cancel() async {
        guard !terminal else { return }
        terminal = true
        finishing = false
        pendingSnapshot = nil
        let task = activeTask
        activeTask = nil
        task?.cancel()
        await http.cancel()
        _ = await task?.value
        activeRequests = 0
        rollingSamples.removeAll(keepingCapacity: false)
        inputResampler.reset()
        requestPartialProjection.reset()
        temporaryFileCount = 0
        if sessionID != nil { emit(.cancelled(metadata())) }
        eventContinuation.finish()
    }

    func diagnosticsSnapshot() -> MiMoSnapshotProviderDiagnostics {
        MiMoSnapshotProviderDiagnostics(
            currentBufferedSamples: rollingSamples.count,
            pendingSnapshots: pendingSnapshot == nil ? 0 : 1,
            activeRequests: activeRequests,
            temporaryFileCount: temporaryFileCount,
            completedRequests: completedRequests,
            maximumBufferedSamples: maximumBufferedSamples,
            maximumPendingSnapshots: maximumPendingSnapshots,
            maximumConcurrentRequests: maximumConcurrentRequests,
            maximumRequestBytes: maximumRequestBytes
        )
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            id: UUID().uuidString,
            samples: rollingSamples,
            sampleRate: sampleRate,
            audioRange: TranscriptionAudioRange(
                start: TimeInterval(rollingStartFrame) / TimeInterval(sampleRate),
                end: TimeInterval(latestEndFrame) / TimeInterval(sampleRate)
            )
        )
    }

    private func schedule(_ snapshot: Snapshot) {
        guard !terminal else { return }
        if activeTask != nil {
            pendingSnapshot = snapshot
            maximumPendingSnapshots = max(maximumPendingSnapshots, 1)
            return
        }
        launch(snapshot)
    }

    private func launch(_ snapshot: Snapshot) {
        requestPartialProjection.begin(
            snapshotID: snapshot.id,
            baselineText: projectedText
        )
        activeRequests = 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
        let http = self.http
        let builder = requestBuilder
        let directory = temporaryDirectory
        let language = self.language
        activeTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let outcome = await Self.performSnapshot(
                snapshot,
                http: http,
                requestBuilder: builder,
                temporaryDirectory: directory,
                language: language,
                observer: self
            )
            await self.requestDidComplete(snapshot, outcome: outcome)
        }
    }

    private nonisolated static func performSnapshot(
        _ snapshot: Snapshot,
        http: any MiMoHTTPStreaming,
        requestBuilder: any MiMoASRRequestBuilding,
        temporaryDirectory: URL,
        language: MiMoASRLanguage,
        observer: MiMoSnapshotProvider
    ) async -> SnapshotOutcome {
        let url = temporaryDirectory.appendingPathComponent("\(snapshot.id).wav")
        var fileCreated = false
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try wavData(samples: snapshot.samples, sampleRate: snapshot.sampleRate).write(to: url, options: .atomic)
            fileCreated = true
            await observer.temporaryFileCreated()
            let data = try Data(contentsOf: url)
            let request = try requestBuilder.makeRequest(wavData: data, language: language)
            await observer.observedRequestBytes(request.httpBody?.count ?? 0)
            let stream = try await http.stream(request)
            var parser = MiMoSSEParser()
            var text = ""
            var completed = false
            for try await chunk in stream {
                try Task.checkCancellation()
                for delta in try parser.append(chunk) {
                    switch delta {
                    case .text(let value):
                        text += value
                        await observer.observedPartial(text, snapshotID: snapshot.id)
                    case .completed:
                        completed = true
                    }
                }
            }
            guard completed else { throw MiMoASRProtocolError.invalidJSON }
            if fileCreated {
                try? FileManager.default.removeItem(at: url)
                await observer.temporaryFileRemoved()
            }
            return .success(text)
        } catch is CancellationError {
            if fileCreated {
                try? FileManager.default.removeItem(at: url)
                await observer.temporaryFileRemoved()
            }
            return .cancelled
        } catch {
            if fileCreated {
                try? FileManager.default.removeItem(at: url)
                await observer.temporaryFileRemoved()
            }
            return .failure(Self.classify(error))
        }
    }

    private func requestDidComplete(_ snapshot: Snapshot, outcome: SnapshotOutcome) async {
        activeTask = nil
        activeRequests = 0
        requestPartialProjection.end(snapshotID: snapshot.id)
        guard !terminal else { return }

        switch outcome {
        case .success(let text):
            completedRequests += 1
            consumeCompletedText(text, snapshot: snapshot)
        case .failure(let failure):
            fail(failure)
            return
        case .cancelled:
            if !terminal { fail(Failure(code: .transportDisconnected, message: "MiMo request cancelled")) }
            return
        }

        if let next = pendingSnapshot {
            pendingSnapshot = nil
            launch(next)
        } else if finishing {
            completeSuccessfully()
        }
    }

    private func consumeCompletedText(_ text: String, snapshot: Snapshot) {
        guard text.count >= projectedText.count else { return }
        lastSnapshotRange = snapshot.audioRange
        let reconciliation = reconciler.consume(SenseVoiceSnapshotRecognition(
            text: text,
            tokens: text.map(String.init),
            tokenTimestamps: nil,
            audioRange: snapshot.audioRange
        ))
        if !reconciliation.newlyConfirmedText.isEmpty {
            emittedConfirmedText += reconciliation.newlyConfirmedText
            finalizedIndex += 1
            emit(.finalized(metadata(), segment: TranscriptSegment(
                id: "mimo-final-\(finalizedIndex)",
                text: reconciliation.newlyConfirmedText,
                audioRange: snapshot.audioRange
            )))
        }
        projectedText = reconciliation.confirmedText + reconciliation.volatileTailText
        partialRevision += 1
        emit(.partial(
            metadata(),
            segmentID: "mimo-volatile",
            revision: partialRevision,
            text: reconciliation.volatileTailText
        ))
    }

    private func observedPartial(_ text: String, snapshotID: String) {
        guard !terminal else { return }
        guard case .emit(let acceptedText) = requestPartialProjection.accept(
            snapshotID: snapshotID,
            incomingText: text
        ) else { return }
        partialRevision += 1
        emit(.partial(
            metadata(),
            segmentID: "mimo-volatile",
            revision: partialRevision,
            text: unconfirmedTail(of: acceptedText)
        ))
    }

    private func unconfirmedTail(of text: String) -> String {
        let confirmed = Array(emittedConfirmedText)
        let incoming = Array(text)
        let maximum = min(confirmed.count, incoming.count)
        if maximum > 0 {
            for length in stride(from: maximum, through: 1, by: -1)
            where Array(confirmed.suffix(length)) == Array(incoming.prefix(length)) {
                return String(incoming.dropFirst(length))
            }
        }
        return text
    }

    private func completeSuccessfully() {
        guard !terminal else { return }
        let remainder = projectedText.hasPrefix(emittedConfirmedText)
            ? String(projectedText.dropFirst(emittedConfirmedText.count))
            : projectedText
        if !remainder.isEmpty {
            finalizedIndex += 1
            emit(.finalized(metadata(), segment: TranscriptSegment(
                id: "mimo-volatile",
                text: remainder,
                audioRange: lastSnapshotRange
            )))
        } else {
            partialRevision += 1
            emit(.partial(metadata(), segmentID: "mimo-volatile", revision: partialRevision, text: ""))
        }
        emit(.completed(metadata()))
        terminal = true
        finishing = false
        pendingSnapshot = nil
        activeRequests = 0
        rollingSamples.removeAll(keepingCapacity: false)
        inputResampler.reset()
        requestPartialProjection.reset()
        eventContinuation.finish()
    }

    private func fail(_ failure: Failure) {
        guard !terminal else { return }
        emit(.failed(metadata(), TranscriptionFailure(
            code: failure.code,
            message: failure.message,
            isRecoverable: true
        )))
        terminal = true
        finishing = false
        pendingSnapshot = nil
        activeRequests = 0
        rollingSamples.removeAll(keepingCapacity: false)
        inputResampler.reset()
        requestPartialProjection.reset()
        eventContinuation.finish()
    }

    private func temporaryFileCreated() { temporaryFileCount += 1 }
    private func temporaryFileRemoved() { temporaryFileCount = max(0, temporaryFileCount - 1) }
    private func observedRequestBytes(_ count: Int) { maximumRequestBytes = max(maximumRequestBytes, count) }

    private func metadata() -> TranscriptionEventMetadata {
        eventSequence &+= 1
        return TranscriptionEventMetadata(
            sessionID: sessionID!,
            providerEpoch: providerEpoch,
            sequence: eventSequence,
            emittedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func emit(_ event: TranscriptionEvent) { eventContinuation.yield(event) }

    private nonisolated static func classify(_ error: Error) -> Failure {
        if let http = error as? MiMoHTTPError {
            switch http {
            case .status(401), .status(403):
                return Failure(code: .providerUnavailable, message: "MiMo credential was rejected")
            case .status(429):
                return Failure(code: .providerUnavailable, message: "MiMo quota or rate limit was reached")
            case .status:
                return Failure(code: .transportDisconnected, message: "MiMo service returned an error")
            case .invalidResponse:
                return Failure(code: .transportDisconnected, message: "MiMo returned an invalid response")
            }
        }
        if error is MiMoASRProtocolError {
            return Failure(code: .providerRejectedInput, message: "MiMo request or response was invalid")
        }
        if let url = error as? URLError, url.code == .timedOut {
            return Failure(code: .transportDisconnected, message: "MiMo request timed out")
        }
        return Failure(code: .transportDisconnected, message: "MiMo request failed")
    }

    private nonisolated static func wavData(samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let value: Int16 = clamped <= -1 ? .min : clamped >= 1 ? .max : Int16((clamped * 32_768).rounded())
            let bits = UInt16(bitPattern: value)
            pcm.append(UInt8(bits & 0xFF))
            pcm.append(UInt8((bits >> 8) & 0xFF))
        }
        var wav = Data("RIFF".utf8)
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.append(Data("WAVEfmt ".utf8))
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(sampleRate * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.append(Data("data".utf8))
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    private struct Snapshot: Sendable {
        let id: String
        let samples: [Float]
        let sampleRate: Int
        let audioRange: TranscriptionAudioRange
    }

    private enum SnapshotOutcome: Sendable {
        case success(String)
        case failure(Failure)
        case cancelled
    }

    private struct Failure: Sendable {
        let code: TranscriptionFailureCode
        let message: String
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
