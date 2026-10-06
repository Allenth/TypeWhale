import Foundation

struct SenseVoiceSnapshotRecognitionOutput: Equatable, Sendable {
    let text: String
    let tokens: [String]
    let tokenTimestamps: [Float]?
}

protocol SenseVoiceSnapshotRecognizing: Sendable {
    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput
}

protocol SenseVoiceShadowResourceAdmitting: Sendable {
    func canStartRecognition() async -> Bool
}

struct AlwaysAdmitSenseVoiceShadowResource: SenseVoiceShadowResourceAdmitting {
    func canStartRecognition() async -> Bool { true }
}

struct ClosureSenseVoiceShadowResourceAdmission: SenseVoiceShadowResourceAdmitting, @unchecked Sendable {
    let check: @Sendable () async -> Bool

    func canStartRecognition() async -> Bool { await check() }
}

struct SenseVoiceSnapshotProviderConfiguration: Equatable, Sendable {
    let firstFastSeconds: TimeInterval
    let fastIntervalSeconds: TimeInterval
    let correctionIntervalSeconds: TimeInterval
    let maximumWindowSeconds: TimeInterval
    let maximumFastWindowSeconds: TimeInterval
    let maximumCorrectionWindowSeconds: TimeInterval
    let maximumRetainedAudioSeconds: TimeInterval
    let maximumServiceMilliseconds: Int
    let schedulerPolicy: SenseVoiceShadowSchedulingPolicy

    init(
        firstFastSeconds: TimeInterval,
        fastIntervalSeconds: TimeInterval,
        correctionIntervalSeconds: TimeInterval,
        maximumWindowSeconds: TimeInterval,
        maximumFastWindowSeconds: TimeInterval,
        maximumCorrectionWindowSeconds: TimeInterval,
        maximumRetainedAudioSeconds: TimeInterval? = nil,
        maximumServiceMilliseconds: Int,
        schedulerPolicy: SenseVoiceShadowSchedulingPolicy
    ) {
        self.firstFastSeconds = firstFastSeconds
        self.fastIntervalSeconds = fastIntervalSeconds
        self.correctionIntervalSeconds = correctionIntervalSeconds
        self.maximumWindowSeconds = maximumWindowSeconds
        self.maximumFastWindowSeconds = maximumFastWindowSeconds
        self.maximumCorrectionWindowSeconds = maximumCorrectionWindowSeconds
        self.maximumRetainedAudioSeconds = max(
            maximumWindowSeconds,
            maximumRetainedAudioSeconds ?? maximumWindowSeconds
        )
        self.maximumServiceMilliseconds = maximumServiceMilliseconds
        self.schedulerPolicy = schedulerPolicy
    }

    static let initial = SenseVoiceSnapshotProviderConfiguration(
        firstFastSeconds: 0.5,
        fastIntervalSeconds: 2,
        correctionIntervalSeconds: 6,
        maximumWindowSeconds: 8,
        maximumFastWindowSeconds: 3,
        maximumCorrectionWindowSeconds: 8,
        maximumRetainedAudioSeconds: 14,
        maximumServiceMilliseconds: 300,
        schedulerPolicy: .initial
    )
}

struct SenseVoiceSnapshotProviderDiagnostics: Equatable, Sendable {
    let acceptedAudioFrames: Int
    let currentBufferedSamples: Int
    let maximumBufferedSamples: Int
    let currentPendingFast: Int
    let maximumPendingFast: Int
    let currentPendingCorrections: Int
    let maximumPendingCorrections: Int
    let correctionDegradedCount: Int
    let resourceDegradedCount: Int
    let admissionSkippedCount: Int
    let currentActiveRecognitions: Int
    let maximumConcurrentRecognitions: Int
    let completedRecognitions: Int
    let maximumProviderServiceMilliseconds: Int
    /// 已喂入音频总时长(毫秒)。
    let audioDurationMilliseconds: Int
    /// 最后一次成功识别覆盖到的音频结束时间(毫秒)。
    let lastRecognizedAudioEndMilliseconds: Int
    /// 停止点与最后识别覆盖点之差(毫秒);completed 时应趋近 0,否则代表尾部漏识别。
    let tailGapMilliseconds: Int
    let discardedFastRequestCount: Int
    let discardedCorrectionRequestCount: Int
    let boundaryCorrectionRequestedCount: Int
    let boundaryCorrectionSucceededCount: Int
    let boundaryCorrectionFailedCount: Int
    let latestSeamConfidence: SeamConfidence?
}

enum SenseVoiceSnapshotProviderError: Error, Equatable {
    case notStarted
    case terminal
    case invalidAudioFrame
}

final class SenseVoiceSnapshotProvider: TranscriptionProvider, @unchecked Sendable {
    let id: String
    let capabilities = TranscriptionProviderCapabilities(
        supportsRealtimePCM: true,
        supportsPartialResults: true,
        supportsServerFinalization: false,
        maximumConcurrentSessions: 1
    )

    private let stream: AsyncStream<TranscriptionEvent>
    private let core: SenseVoiceSnapshotProviderCore

    init(
        id: String = "sensevoice-snapshot-shadow",
        recognizer: any SenseVoiceSnapshotRecognizing,
        configuration: SenseVoiceSnapshotProviderConfiguration = .initial,
        admission: any SenseVoiceShadowResourceAdmitting = AlwaysAdmitSenseVoiceShadowResource()
    ) {
        self.id = id
        var captured: AsyncStream<TranscriptionEvent>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        guard let continuation = captured else {
            preconditionFailure("SenseVoiceSnapshotProvider continuation was not created")
        }
        core = SenseVoiceSnapshotProviderCore(
            recognizer: recognizer,
            configuration: configuration,
            admission: admission,
            continuation: continuation
        )
    }

    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws {
        try await core.start(sessionID: sessionID, providerEpoch: providerEpoch)
    }

    func append(_ frame: AudioFrame) async throws {
        try await core.append(frame)
    }

    func finish() async throws {
        await core.finish()
    }

    func cancel() async {
        await core.cancel()
    }

    func events() -> AsyncStream<TranscriptionEvent> { stream }

    func diagnostics() async -> SenseVoiceSnapshotProviderDiagnostics {
        await core.diagnostics()
    }
}

private actor SenseVoiceSnapshotProviderCore {
    private let recognizer: any SenseVoiceSnapshotRecognizing
    private let configuration: SenseVoiceSnapshotProviderConfiguration
    private let admission: any SenseVoiceShadowResourceAdmitting
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let boundaryCorrectionPlanner = RealtimeBoundaryCorrectionPlanner(
        preRollSeconds: 4,
        postRollSeconds: 4
    )
    private let hallucinationFilter = RealtimeRecognitionHallucinationFilter()
    private var scheduler: SenseVoiceShadowScheduler
    private var reconciler = SenseVoiceBoundaryReconciler()
    private var sessionID: TranscriptionSessionID?
    private var providerEpoch = 0
    private var sequence: UInt64 = 0
    private var rollingSamples: [Float] = []
    private var sampleRate = 0
    private var totalFrames: Int64 = 0
    private var nextFastFrame: Int64 = 0
    private var nextCorrectionFrame: Int64 = 0
    private var commitHorizon = 0
    private var partialRevision = 0
    private var confirmedSegmentIndex = 0
    private var confirmedAudioEndTime: TimeInterval?
    private var acceptsFrames = false
    private var finishRequested = false
    private var terminal = false
    private var recognitionTask: Task<Void, Never>?
    private var acceptedAudioFrames = 0
    private var maximumBufferedSamples = 0
    private var correctionDegradedCount = 0
    private var resourceDegradedCount = 0
    private var admissionSkippedCount = 0
    private var activeRecognitions = 0
    private var maximumConcurrentRecognitions = 0
    private var completedRecognitions = 0
    private var maximumProviderServiceMilliseconds = 0
    /// 最后一次成功识别覆盖到的音频结束时间;用于对比停止点算尾部覆盖差。
    private var lastRecognizedAudioEndTime: TimeInterval = 0
    private var boundaryCorrectionRequestedCount = 0
    private var boundaryCorrectionSucceededCount = 0
    private var boundaryCorrectionFailedCount = 0
    private var latestSeamConfidence: SeamConfidence?

    init(
        recognizer: any SenseVoiceSnapshotRecognizing,
        configuration: SenseVoiceSnapshotProviderConfiguration,
        admission: any SenseVoiceShadowResourceAdmitting,
        continuation: AsyncStream<TranscriptionEvent>.Continuation
    ) {
        self.recognizer = recognizer
        self.configuration = configuration
        self.admission = admission
        self.continuation = continuation
        scheduler = SenseVoiceShadowScheduler(policy: configuration.schedulerPolicy)
    }

    func start(
        sessionID: TranscriptionSessionID,
        providerEpoch: Int
    ) throws {
        guard !terminal else { throw SenseVoiceSnapshotProviderError.terminal }
        self.sessionID = sessionID
        self.providerEpoch = providerEpoch
        acceptsFrames = true
    }

    func append(_ frame: AudioFrame) throws {
        guard sessionID != nil else { throw SenseVoiceSnapshotProviderError.notStarted }
        guard acceptsFrames, !terminal else { throw SenseVoiceSnapshotProviderError.terminal }
        guard frame.sampleRate > 0,
              frame.channelCount == 1,
              !frame.samples.isEmpty,
              frame.samples.allSatisfy(\.isFinite) else {
            throw SenseVoiceSnapshotProviderError.invalidAudioFrame
        }

        if sampleRate == 0 {
            sampleRate = frame.sampleRate
            nextFastFrame = Int64(Double(sampleRate) * max(0, configuration.firstFastSeconds))
            nextCorrectionFrame = Int64(Double(sampleRate) * max(0, configuration.correctionIntervalSeconds))
        } else if sampleRate != frame.sampleRate {
            throw SenseVoiceSnapshotProviderError.invalidAudioFrame
        }

        acceptedAudioFrames += 1
        totalFrames += Int64(frame.samples.count)
        rollingSamples.append(contentsOf: frame.samples)
        let maximumSamples = max(
            1,
            Int(Double(sampleRate) * max(0.1, configuration.maximumRetainedAudioSeconds))
        )
        if rollingSamples.count > maximumSamples {
            rollingSamples.removeFirst(rollingSamples.count - maximumSamples)
        }
        maximumBufferedSamples = max(maximumBufferedSamples, rollingSamples.count)

        if totalFrames >= nextFastFrame {
            enqueue(kind: .fast)
            nextFastFrame = totalFrames + Int64(Double(sampleRate) * max(0.01, configuration.fastIntervalSeconds))
        }
        if totalFrames >= nextCorrectionFrame {
            commitHorizon += 1
            enqueue(kind: .correction)
            nextCorrectionFrame = totalFrames + Int64(Double(sampleRate) * max(0.1, configuration.correctionIntervalSeconds))
        }
        launchNextIfNeeded()
    }

    func finish() {
        acceptsFrames = false
        finishRequested = true
        enqueueFinalTailSnapshotIfNeeded()
        launchNextIfNeeded()
        completeIfDrained()
    }

    func cancel() {
        acceptsFrames = false
        terminal = true
        recognitionTask?.cancel()
        recognitionTask = nil
        _ = scheduler.cancelAll()
        rollingSamples.removeAll(keepingCapacity: false)
        continuation.finish()
    }

    func diagnostics() -> SenseVoiceSnapshotProviderDiagnostics {
        let audioDurationMilliseconds = Int(
            (Double(totalFrames) / Double(max(1, sampleRate))) * 1_000
        )
        let lastRecognizedAudioEndMilliseconds = Int(lastRecognizedAudioEndTime * 1_000)
        let tailGapMilliseconds = max(
            0,
            audioDurationMilliseconds - lastRecognizedAudioEndMilliseconds
        )
        return SenseVoiceSnapshotProviderDiagnostics(
            acceptedAudioFrames: acceptedAudioFrames,
            currentBufferedSamples: rollingSamples.count,
            maximumBufferedSamples: maximumBufferedSamples,
            currentPendingFast: scheduler.pendingFastCount,
            maximumPendingFast: scheduler.maximumObservedPendingFast,
            currentPendingCorrections: scheduler.pendingCorrectionCount,
            maximumPendingCorrections: scheduler.maximumObservedPendingCorrections,
            correctionDegradedCount: correctionDegradedCount,
            resourceDegradedCount: resourceDegradedCount,
            admissionSkippedCount: admissionSkippedCount,
            currentActiveRecognitions: activeRecognitions,
            maximumConcurrentRecognitions: maximumConcurrentRecognitions,
            completedRecognitions: completedRecognitions,
            maximumProviderServiceMilliseconds: maximumProviderServiceMilliseconds,
            audioDurationMilliseconds: audioDurationMilliseconds,
            lastRecognizedAudioEndMilliseconds: lastRecognizedAudioEndMilliseconds,
            tailGapMilliseconds: tailGapMilliseconds,
            discardedFastRequestCount: scheduler.discardedFastRequestCount,
            discardedCorrectionRequestCount: scheduler.discardedCorrectionRequestCount,
            boundaryCorrectionRequestedCount: boundaryCorrectionRequestedCount,
            boundaryCorrectionSucceededCount: boundaryCorrectionSucceededCount,
            boundaryCorrectionFailedCount: boundaryCorrectionFailedCount,
            latestSeamConfidence: latestSeamConfidence
        )
    }

    private func enqueue(kind: SenseVoiceShadowRequestKind) {
        let windowSeconds: TimeInterval = kind == .fast
            ? configuration.maximumFastWindowSeconds
            : configuration.maximumCorrectionWindowSeconds
        let requestSampleLimit = max(1, Int(Double(sampleRate) * max(0.1, windowSeconds)))
        let requestSamples = Array(rollingSamples.suffix(requestSampleLimit))
        let end = Double(totalFrames) / Double(max(1, sampleRate))
        let start = max(0, end - Double(requestSamples.count) / Double(max(1, sampleRate)))
        let previousState = scheduler.state
        _ = scheduler.enqueue(SenseVoiceShadowRequest(
            id: UUID().uuidString,
            kind: kind,
            commitHorizon: commitHorizon,
            samples: requestSamples,
            sampleRate: sampleRate,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime,
            audioStartTime: start,
            audioEndTime: end
        ))
        if previousState == .active,
           scheduler.state == .degraded(.correctionCapacityExceeded) {
            correctionDegradedCount += 1
            emit(.failed(
                metadata(),
                TranscriptionFailure(
                    code: .providerRejectedInput,
                    message: "SenseVoice shadow capacity exceeded",
                    isRecoverable: true
                )
            ))
        }
    }

    private func enqueueFinalTailSnapshotIfNeeded() {
        guard sampleRate > 0,
              !rollingSamples.isEmpty,
              recognitionTask == nil,
              scheduler.isIdle else { return }
        let requestSampleLimit = max(
            1,
            Int(Double(sampleRate) * max(0.1, configuration.maximumCorrectionWindowSeconds))
        )
        let requestSamples = Array(rollingSamples.suffix(requestSampleLimit))
        let end = Double(totalFrames) / Double(max(1, sampleRate))
        let start = max(0, end - Double(requestSamples.count) / Double(max(1, sampleRate)))
        commitHorizon += 1
        _ = scheduler.enqueueFinalTail(SenseVoiceShadowRequest(
            id: UUID().uuidString,
            kind: .correction,
            commitHorizon: commitHorizon,
            samples: requestSamples,
            sampleRate: sampleRate,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime,
            audioStartTime: start,
            audioEndTime: end
        ))
    }

    private func launchNextIfNeeded() {
        guard recognitionTask == nil,
              let request = scheduler.admitNextIfIdle() else {
            completeIfDrained()
            return
        }
        launch(request)
    }

    private func launch(_ request: SenseVoiceShadowRequest) {
        activeRecognitions += 1
        maximumConcurrentRecognitions = max(maximumConcurrentRecognitions, activeRecognitions)
        let recognizer = self.recognizer
        let admission = self.admission
        recognitionTask = Task { [weak self] in
            guard await admission.canStartRecognition() else {
                await self?.recognitionSkipped(request: request)
                return
            }
            let started = ProcessInfo.processInfo.systemUptime
            let result: Result<SenseVoiceSnapshotRecognitionOutput, Error>
            do {
                result = .success(try await recognizer.recognize(
                    samples: request.samples,
                    sampleRate: request.sampleRate
                ))
            } catch {
                result = .failure(error)
            }
            let serviceMilliseconds = max(
                0,
                Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            )
            await self?.recognitionCompleted(
                request: request,
                result: result,
                serviceMilliseconds: serviceMilliseconds
            )
        }
    }

    private func recognitionSkipped(request: SenseVoiceShadowRequest) {
        recognitionTask = nil
        activeRecognitions = max(0, activeRecognitions - 1)
        admissionSkippedCount += 1
        if let next = scheduler.complete(activeRequestID: request.id) {
            launch(next)
        } else {
            completeIfDrained()
        }
    }

    private func recognitionCompleted(
        request: SenseVoiceShadowRequest,
        result: Result<SenseVoiceSnapshotRecognitionOutput, Error>,
        serviceMilliseconds: Int
    ) {
        recognitionTask = nil
        activeRecognitions = max(0, activeRecognitions - 1)
        completedRecognitions += 1
        maximumProviderServiceMilliseconds = max(
            maximumProviderServiceMilliseconds,
            serviceMilliseconds
        )

        let serviceBudget = max(1, configuration.maximumServiceMilliseconds)
        if serviceMilliseconds > serviceBudget {
            resourceDegradedCount += 1
        }

        if !terminal {
            switch result {
            case .success(let output):
                lastRecognizedAudioEndTime = max(lastRecognizedAudioEndTime, request.audioEndTime)
                apply(output, request: request)
            case .failure(let error):
                emit(.failed(
                    metadata(),
                    TranscriptionFailure(
                        code: .providerUnavailable,
                        message: String(describing: error),
                        isRecoverable: true
                    )
                ))
            }
        }

        if let next = scheduler.complete(activeRequestID: request.id) {
            launch(next)
        } else {
            completeIfDrained()
        }
    }

    private func apply(
        _ output: SenseVoiceSnapshotRecognitionOutput,
        request: SenseVoiceShadowRequest
    ) {
        let authority: RealtimeRecognitionHallucinationFilter.Authority
        switch request.kind {
        case .fast:
            authority = .fast
        case .correction, .boundaryCorrection:
            authority = .correction
        }
        switch hallucinationFilter.evaluate(
            text: output.text,
            previousPreviewText: reconciler.currentDisplayText,
            authority: authority
        ) {
        case .suppress(let reason):
            LaunchDiagnostics.markAsync(
                "realtime_result_suppressed path=sensevoice_provider kind=\(request.kind) reason=\(reason.rawValue)"
            )
            return
        case .keep:
            break
        }
        let recognition = SenseVoiceSnapshotRecognition(
            text: output.text,
            tokens: output.tokens,
            tokenTimestamps: output.tokenTimestamps,
            audioRange: TranscriptionAudioRange(
                start: request.audioStartTime,
                end: request.audioEndTime
            )
        )
        let reconciliation: SenseVoiceBoundaryReconciliation
        if request.kind == .boundaryCorrection {
            reconciliation = reconciler.consumeBoundaryCorrection(recognition)
            boundaryCorrectionSucceededCount += 1
            LaunchDiagnostics.markAsync(
                "boundary_correction_done outcome=success seam_confidence=boundaryCorrected"
            )
        } else {
            reconciliation = reconciler.consume(recognition)
        }
        latestSeamConfidence = reconciliation.seamConfidence
        if reconciliation.recoveryRequired,
           request.kind != .boundaryCorrection {
            enqueueBoundaryCorrectionIfPossible(
                boundaryTime: reconciliation.confirmedThroughTime ?? request.audioStartTime,
                kind: .conflictRecovery
            )
        }
        var finalizedSegments: [TranscriptSegment] = []
        if !reconciliation.newlyConfirmedText.isEmpty {
            confirmedSegmentIndex += 1
            let reportedEnd = reconciliation.confirmedThroughTime ?? request.audioEndTime
            let segmentStart = confirmedAudioEndTime ?? min(request.audioStartTime, reportedEnd)
            let segmentEnd = max(segmentStart, reportedEnd)
            confirmedAudioEndTime = segmentEnd
            finalizedSegments.append(TranscriptSegment(
                id: "sensevoice-confirmed-\(confirmedSegmentIndex)",
                text: reconciliation.newlyConfirmedText,
                audioRange: TranscriptionAudioRange(
                    start: segmentStart,
                    end: segmentEnd
                )
            ))
        }
        partialRevision += 1
        emit(.reconciled(
            metadata(),
            finalizedSegments: finalizedSegments,
            volatileSegmentID: "sensevoice-tail",
            revision: partialRevision,
            text: reconciliation.volatileTailText
        ))
    }

    private func completeIfDrained() {
        guard finishRequested,
              !terminal,
              recognitionTask == nil,
              scheduler.isIdle else { return }
        terminal = true
        emit(.completed(metadata()))
        rollingSamples.removeAll(keepingCapacity: false)
        continuation.finish()
    }

    private func enqueueBoundaryCorrectionIfPossible(
        boundaryTime: TimeInterval,
        kind: RealtimeBoundaryKind
    ) {
        guard sampleRate > 0, !rollingSamples.isEmpty else { return }
        let availableAudioEnd = Double(totalFrames) / Double(max(1, sampleRate))
        let availableAudioStart = max(
            0,
            availableAudioEnd - Double(rollingSamples.count) / Double(max(1, sampleRate))
        )
        guard let plan = boundaryCorrectionPlanner.plan(
            boundaryTime: boundaryTime,
            availableAudioStart: availableAudioStart,
            availableAudioEnd: availableAudioEnd,
            kind: kind
        ), let window = samples(in: plan) else {
            boundaryCorrectionFailedCount += 1
            return
        }
        boundaryCorrectionRequestedCount += 1
        LaunchDiagnostics.markAsync(
            "boundary_correction_start boundary_ms=\(Int(plan.boundaryTime * 1_000)) range_ms=\(Int(plan.audioStartTime * 1_000))...\(Int(plan.audioEndTime * 1_000))"
        )
        commitHorizon += 1
        _ = scheduler.enqueue(SenseVoiceShadowRequest(
            id: UUID().uuidString,
            kind: .boundaryCorrection,
            commitHorizon: commitHorizon,
            samples: window.samples,
            sampleRate: sampleRate,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime,
            audioStartTime: window.start,
            audioEndTime: window.end
        ))
    }

    private func samples(
        in plan: RealtimeBoundaryCorrectionPlan
    ) -> (samples: [Float], start: TimeInterval, end: TimeInterval)? {
        guard sampleRate > 0, plan.audioEndTime > plan.audioStartTime else { return nil }
        let availableAudioEnd = Double(totalFrames) / Double(max(1, sampleRate))
        let availableAudioStart = max(
            0,
            availableAudioEnd - Double(rollingSamples.count) / Double(max(1, sampleRate))
        )
        let start = max(plan.audioStartTime, availableAudioStart)
        let end = min(plan.audioEndTime, availableAudioEnd)
        guard end > start else { return nil }
        let startOffset = max(0, Int(((start - availableAudioStart) * Double(sampleRate)).rounded(.down)))
        let endOffset = min(
            rollingSamples.count,
            Int(((end - availableAudioStart) * Double(sampleRate)).rounded(.up))
        )
        guard endOffset > startOffset,
              rollingSamples.indices.contains(startOffset),
              endOffset <= rollingSamples.count else {
            return nil
        }
        return (Array(rollingSamples[startOffset..<endOffset]), start, end)
    }

    private func metadata() -> TranscriptionEventMetadata {
        sequence += 1
        return TranscriptionEventMetadata(
            sessionID: sessionID!,
            providerEpoch: providerEpoch,
            sequence: sequence,
            emittedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func emit(_ event: TranscriptionEvent) {
        continuation.yield(event)
    }
}
