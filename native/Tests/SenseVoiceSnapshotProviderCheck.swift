import Foundation

@main
struct SenseVoiceSnapshotProviderCheck {
    static func main() async throws {
        let recognizer = StubSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-check",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 0.1,
                fastIntervalSeconds: 0.1,
                correctionIntervalSeconds: 0.3,
                maximumWindowSeconds: 0.6,
                maximumFastWindowSeconds: 0.2,
                maximumCorrectionWindowSeconds: 0.5,
                maximumServiceMilliseconds: 1_000,
                schedulerPolicy: .initial
            )
        )
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let session = TranscriptionSession(sessionID: sessionID, provider: provider)
        let eventStream = await session.events()
        let collector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        try await session.start()
        for index in 0..<12 {
            try await session.append(AudioFrame(
                samples: [Float(index) / 12],
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }
        await session.finish()
        let events = await collector.value
        let finalState = await session.currentState()
        let diagnostics = await provider.diagnostics()
        let recognizerMaximumConcurrentCalls = await recognizer.maximumConcurrentCalls
        let recognizerMaximumSamples = await recognizer.maximumSamples

        precondition(events.contains { if case .reconciled = $0 { return true }; return false })
        precondition(!events.contains {
            switch $0 {
            case .partial, .finalized: return true
            default: return false
            }
        })
        precondition(events.contains { if case .completed = $0 { return true }; return false })
        precondition(finalState.lifecycle == .completed)
        precondition(diagnostics.maximumPendingFast <= 1)
        precondition(diagnostics.maximumPendingCorrections <= 2)
        precondition(diagnostics.maximumConcurrentRecognitions == 1)
        precondition(diagnostics.acceptedAudioFrames == 12)
        precondition(diagnostics.maximumBufferedSamples <= 6)
        precondition(diagnostics.resourceDegradedCount == 0)
        precondition(recognizerMaximumConcurrentCalls == 1)
        precondition(recognizerMaximumSamples <= 5)

        try await productionBusyAdmissionSkipsShadowWork()
        try await finishEnqueuesTailSnapshotBeforeCompleting()
        try await slowSingleShadowRecognitionStillPublishesText()
        try await slowShadowRecognitionDoesNotPermanentlyMuteCandidate()
        try await continuousSpeechAccumulatesAcrossCorrectionWindows()
        try await tenMinuteContinuousPCMRemainsBoundedAndCleansUp()

        print("SenseVoiceSnapshotProviderCheck passed")
    }

    private static func continuousSpeechAccumulatesAcrossCorrectionWindows() async throws {
        let recognizer = TimelineSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-continuous-accumulation",
            recognizer: recognizer,
            configuration: .initial
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        let stateStream = await session.states()
        let eventStream = await session.events()
        let stateCollector = Task { () -> [TranscriptState] in
            var states: [TranscriptState] = []
            for await state in stateStream { states.append(state) }
            return states
        }
        let eventCollector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        try await session.start()
        let sampleRate = 10
        for second in 0..<30 {
            try await session.append(AudioFrame(
                samples: Array(repeating: Float(second), count: sampleRate),
                sampleRate: sampleRate,
                channelCount: 1,
                startFrame: Int64(second * sampleRate)
            ))
            await waitUntilProviderIdle(provider)
        }
        await session.finish()
        let states = await stateCollector.value
        let events = await eventCollector.value
        let correctionRanges = await recognizer.correctionRanges
        let diagnostics = await provider.diagnostics()

        precondition(correctionRanges.count >= 3, "30 seconds should produce multiple correction snapshots")
        precondition(
            zip(correctionRanges, correctionRanges.dropFirst()).contains { previous, current in
                current.startSecond <= previous.endSecond
            },
            "continuous speech should still produce overlapping correction evidence"
        )

        let runningStates = states.filter { $0.lifecycle == .running }
        let firstConfirmed = runningStates.first { !$0.confirmedText.isEmpty }?.confirmedText
        precondition(firstConfirmed != nil, "continuous speech must advance confirmed text")
        precondition(
            runningStates.allSatisfy { $0.failure == nil },
            "healthy overlapping snapshots must not publish a candidate-clearing failure"
        )
        let atomicSnapshots = events.filter {
            if case .reconciled = $0 { return true }
            return false
        }
        let splitTranscriptMutations = events.filter {
            switch $0 {
            case .partial, .finalized: return true
            default: return false
            }
        }
        precondition(
            atomicSnapshots.count == diagnostics.completedRecognitions,
            "each successful local recognition must publish exactly one atomic transcript event"
        )
        precondition(
            splitTranscriptMutations.isEmpty,
            "local snapshots must not split one recognition into finalized/partial redraws"
        )
        if let firstConfirmed {
            for state in runningStates where !state.confirmedText.isEmpty {
                precondition(
                    state.confirmedText.hasPrefix(firstConfirmed),
                    "confirmed transcript must remain append-only"
                )
            }
        }
        let confirmedSegments = states.last?.confirmedSegments ?? []
        for segment in confirmedSegments {
            precondition(segment.audioRange.start <= segment.audioRange.end)
        }
        for (previous, current) in zip(confirmedSegments, confirmedSegments.dropFirst()) {
            precondition(
                current.audioRange.start >= previous.audioRange.end,
                "confirmed segment audio ranges must advance without overlap"
            )
        }
    }

    private static func waitUntilProviderIdle(_ provider: SenseVoiceSnapshotProvider) async {
        for _ in 0..<1_000 {
            let diagnostics = await provider.diagnostics()
            if diagnostics.currentActiveRecognitions == 0,
               diagnostics.currentPendingFast == 0,
               diagnostics.currentPendingCorrections == 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("SenseVoice snapshot provider did not drain scheduled work")
    }

    private static func finishEnqueuesTailSnapshotBeforeCompleting() async throws {
        let recognizer = TailSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-finish-tail",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 10,
                fastIntervalSeconds: 10,
                correctionIntervalSeconds: 10,
                maximumWindowSeconds: 10,
                maximumFastWindowSeconds: 10,
                maximumCorrectionWindowSeconds: 10,
                maximumServiceMilliseconds: 1_000,
                schedulerPolicy: .initial
            )
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )

        try await session.start()
        for index in 0..<5 {
            try await session.append(AudioFrame(
                samples: [Float(index)],
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }
        await session.finish()
        for _ in 0..<1_000 {
            if await session.currentState().lifecycle == .completed { break }
            await Task.yield()
        }

        let state = await session.currentState()
        let diagnostics = await provider.diagnostics()
        precondition(state.lifecycle == .completed)
        precondition(
            state.confirmedText + state.volatileText == "尾部样本4",
            "finish must recognize the latest buffered audio before completed"
        )
        precondition(diagnostics.completedRecognitions == 1)
    }

    private static func tenMinuteContinuousPCMRemainsBoundedAndCleansUp() async throws {
        let recognizer = StubSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-ten-minute-capacity",
            recognizer: recognizer,
            configuration: .initial
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        try await session.start()
        let frameSamples = Array(repeating: Float.zero, count: 1_600)
        for index in 0..<6_000 {
            try await session.append(AudioFrame(
                samples: frameSamples,
                sampleRate: 16_000,
                channelCount: 1,
                startFrame: Int64(index * frameSamples.count)
            ))
        }
        await session.finish()
        for _ in 0..<10_000 {
            if await session.currentState().lifecycle == .completed { break }
            await Task.yield()
        }

        let diagnostics = await provider.diagnostics()
        precondition(diagnostics.acceptedAudioFrames == 6_000)
        precondition(diagnostics.maximumBufferedSamples <= 224_000)
        precondition(diagnostics.currentBufferedSamples == 0)
        precondition(diagnostics.currentPendingFast == 0)
        precondition(diagnostics.currentPendingCorrections == 0)
        precondition(diagnostics.currentActiveRecognitions == 0)
        precondition(diagnostics.maximumPendingFast <= 1)
        precondition(diagnostics.maximumPendingCorrections <= 2)
        precondition(diagnostics.maximumConcurrentRecognitions == 1)
    }

    private static func productionBusyAdmissionSkipsShadowWork() async throws {
        let recognizer = StubSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-denied",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 0.1,
                fastIntervalSeconds: 0.1,
                correctionIntervalSeconds: 1,
                maximumWindowSeconds: 1,
                maximumFastWindowSeconds: 0.2,
                maximumCorrectionWindowSeconds: 0.5,
                maximumServiceMilliseconds: 1_000,
                schedulerPolicy: .initial
            ),
            admission: DenySenseVoiceShadowAdmission()
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        try await session.start()
        for index in 0..<3 {
            try await session.append(AudioFrame(
                samples: [0],
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }
        await session.finish()
        for _ in 0..<1_000 {
            let state = await session.currentState()
            if state.lifecycle == .completed { break }
            await Task.yield()
        }
        let diagnostics = await provider.diagnostics()
        let calls = await recognizer.callCount
        precondition(diagnostics.admissionSkippedCount >= 1)
        precondition(calls == 0)
    }

    private static func slowSingleShadowRecognitionStillPublishesText() async throws {
        let recognizer = AlwaysSlowSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-slow-single-publishes",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 0.1,
                fastIntervalSeconds: 10,
                correctionIntervalSeconds: 10,
                maximumWindowSeconds: 1,
                maximumFastWindowSeconds: 0.5,
                maximumCorrectionWindowSeconds: 1,
                maximumServiceMilliseconds: 1,
                schedulerPolicy: .initial
            )
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        try await session.start()
        for index in 0..<2 {
            try await session.append(AudioFrame(
                samples: [Float(index)],
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }
        await session.finish()
        await waitUntilProviderIdle(provider)
        for _ in 0..<1_000 {
            if await session.currentState().lifecycle == .completed { break }
            await Task.yield()
        }
        let finalState = await session.currentState()
        let diagnostics = await provider.diagnostics()
        let displayText = finalState.confirmedText + finalState.volatileText

        precondition(diagnostics.resourceDegradedCount >= 1)
        precondition(
            displayText == "慢也要显示",
            "slow but successful local recognition must still feed the candidate transcript"
        )
    }

    private static func slowShadowRecognitionDoesNotPermanentlyMuteCandidate() async throws {
        let recognizer = SlowFirstSenseVoiceSnapshotRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-slow-first-recovers",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 0.1,
                fastIntervalSeconds: 0.1,
                correctionIntervalSeconds: 10,
                maximumWindowSeconds: 1,
                maximumFastWindowSeconds: 0.5,
                maximumCorrectionWindowSeconds: 1,
                maximumServiceMilliseconds: 1,
                schedulerPolicy: .initial
            )
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        let eventStream = await session.events()
        let collector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        try await session.start()
        for index in 0..<10 {
            try await session.append(AudioFrame(
                samples: [Float(index)],
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }
        await session.finish()
        await waitUntilProviderIdle(provider)
        let events = await collector.value
        let finalState = await session.currentState()
        let diagnostics = await provider.diagnostics()

        precondition(
            diagnostics.resourceDegradedCount >= 1,
            "slow shadow recognition should still be recorded diagnostically"
        )
        precondition(
            diagnostics.discardedFastRequestCount >= 1,
            "provider diagnostics must expose fast requests replaced while a slow recognition is active"
        )
        precondition(
            !events.contains { if case .failed = $0 { return true }; return false },
            "slow shadow recognition must not publish a UI-clearing failure"
        )
        precondition(
            events.contains { event in
                if case .reconciled(_, _, _, _, let text) = event { return !text.isEmpty }
                return false
            },
            "candidate must recover and receive transcript text after a slow recognition"
        )
        precondition(
            !(finalState.confirmedText + finalState.volatileText).isEmpty,
            "candidate state must not finish empty solely because one shadow recognition was slow"
        )
    }
}

private actor StubSenseVoiceSnapshotRecognizer: SenseVoiceSnapshotRecognizing {
    private(set) var callCount = 0
    private var concurrentCalls = 0
    private(set) var maximumConcurrentCalls = 0
    private(set) var maximumSamples = 0

    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        callCount += 1
        maximumSamples = max(maximumSamples, samples.count)
        concurrentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
        defer { concurrentCalls -= 1 }
        try? await Task.sleep(nanoseconds: 2_000_000)
        let text = callCount < 3 ? "今天" : "今天讨论在线模型"
        return SenseVoiceSnapshotRecognitionOutput(
            text: text,
            tokens: text.map(String.init),
            tokenTimestamps: nil
        )
    }
}

private actor TimelineSenseVoiceSnapshotRecognizer: SenseVoiceSnapshotRecognizing {
    struct AudioRange: CustomStringConvertible, Sendable {
        let startSecond: Int
        let endSecond: Int

        var description: String { "\(startSecond)...\(endSecond)" }
    }

    private(set) var correctionRanges: [AudioRange] = []
    private var callCount = 0

    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        callCount += 1
        let seconds = samples.reduce(into: [Int]()) { result, sample in
            let second = Int(sample.rounded())
            if result.last != second { result.append(second) }
        }
        if seconds.count > 4, let first = seconds.first, let last = seconds.last {
            correctionRanges.append(AudioRange(startSecond: first, endSecond: last))
        }
        let tokens = seconds.map { "[\($0)]" }
        return SenseVoiceSnapshotRecognitionOutput(
            text: tokens.joined(),
            tokens: tokens,
            tokenTimestamps: nil
        )
    }
}

private actor TailSnapshotRecognizer: SenseVoiceSnapshotRecognizing {
    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        let last = Int(samples.last ?? -1)
        let text = "尾部样本\(last)"
        return SenseVoiceSnapshotRecognitionOutput(
            text: text,
            tokens: Array(text).map(String.init),
            tokenTimestamps: nil
        )
    }
}

private struct DenySenseVoiceShadowAdmission: SenseVoiceShadowResourceAdmitting {
    func canStartRecognition() async -> Bool { false }
}

private actor AlwaysSlowSenseVoiceSnapshotRecognizer: SenseVoiceSnapshotRecognizing {
    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        try await Task.sleep(nanoseconds: 20_000_000)
        let text = "慢也要显示"
        return SenseVoiceSnapshotRecognitionOutput(
            text: text,
            tokens: Array(text).map(String.init),
            tokenTimestamps: nil
        )
    }
}

private actor SlowFirstSenseVoiceSnapshotRecognizer: SenseVoiceSnapshotRecognizing {
    private var callCount = 0

    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        callCount += 1
        if callCount == 1 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let text = callCount == 1 ? "慢" : "慢后继续"
        return SenseVoiceSnapshotRecognitionOutput(
            text: text,
            tokens: Array(text).map(String.init),
            tokenTimestamps: nil
        )
    }
}
