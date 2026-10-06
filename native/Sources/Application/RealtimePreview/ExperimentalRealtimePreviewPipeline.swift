import AVFAudio
import Foundation

@MainActor
final class ExperimentalRealtimePreviewPipeline {
    private static let fastQueueBudgetMilliseconds = 700
    private static let correctionBacklogWarningThreshold = 2
    private static let stopFinalizationDeadlineSeconds: TimeInterval = 3
    private static func previewTimeoutSeconds(for request: PreviewPipelineRequest) -> TimeInterval {
        switch request.lane {
        case .fast:
            return 2.5
        case .correction:
            return max(6, min(12, request.audioRange.duration * 2 + 2))
        case .stopTail:
            return max(6, min(14, request.audioRange.duration * 2 + 3))
        }
    }

    private let sessionID: UUID
    private let epoch: Int
    private let configuration: ASRConfiguration
    private let transcriber: NativeSenseVoiceBridge
    private let hallucinationFilter = RealtimeRecognitionHallucinationFilter()
    private var scheduler: PreviewRequestScheduler
    private var reducer: PreviewTranscriptReducer
    private let transcriptTrace: RealtimeTranscriptTrace
    private let onState: (PreviewTranscriptState) -> Void
    private var acceptsNewRequests = true
    private var drainCompletion: ((PreviewTranscriptState) -> Void)?
    private var tailFinalizationRequest: PreviewPipelineRequest?
    private var stopFinalizationDeadlineWorkItem: DispatchWorkItem?
    private var timeoutWorkItemsByRequestID: [UUID: DispatchWorkItem] = [:]

    init(
        sessionID: UUID,
        epoch: Int,
        configuration: ASRConfiguration,
        transcriber: NativeSenseVoiceBridge,
        transcriptTrace: RealtimeTranscriptTrace? = nil,
        onState: @escaping (PreviewTranscriptState) -> Void
    ) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.configuration = configuration
        self.transcriber = transcriber
        self.scheduler = PreviewRequestScheduler(sessionID: sessionID, epoch: epoch)
        self.reducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: epoch)
        self.transcriptTrace = transcriptTrace ?? RealtimeTranscriptTrace(sessionID: sessionID)
        self.onState = onState
    }

    var state: PreviewTranscriptState { reducer.state }

    func markRecoveryRequested() {
        onState(reducer.markRecoveryRequested())
    }

    func receiveFast(_ request: RealtimeSnapshotRequest) {
        guard acceptsNewRequests else { return }
        let audioURL: URL
        do {
            audioURL = try makeFastPreviewAudioFile(request)
        } catch {
            LaunchDiagnostics.markAsync(
                "preview_fast_audio_materialize_failed chunk=\(request.chunkIndex) error=\(error.localizedDescription)"
            )
            return
        }
        let pipelineRequest = PreviewPipelineRequest(
            sessionID: request.taskID,
            epoch: epoch,
            requestID: UUID(),
            chunkID: request.chunkIndex,
            lane: .fast,
            audioURL: audioURL,
            audioRange: request.audioRange,
            boundary: nil,
            enqueuedUptime: ProcessInfo.processInfo.systemUptime
        )
        if let admitted = scheduler.enqueueFast(pipelineRequest) {
            execute(admitted)
        }
        removeDiscardedRequests()
    }

    private func makeFastPreviewAudioFile(_ request: RealtimeSnapshotRequest) throws -> URL {
        guard !request.samples.isEmpty,
              request.sampleRate > 0,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: Double(request.sampleRate),
                  channels: 1
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(request.samples.count)
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(request.samples.count)
        request.samples.withUnsafeBufferPointer { source in
            guard let sourceBase = source.baseAddress,
                  let destination = buffer.floatChannelData?[0] else { return }
            destination.update(from: sourceBase, count: source.count)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            ".preview-fast-\(request.taskID.uuidString)-\(UUID().uuidString.prefix(8)).wav"
        )
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func receiveCorrection(_ snapshot: ExperimentalPreviewAudioSnapshot) {
        guard acceptsNewRequests else {
            try? FileManager.default.removeItem(at: snapshot.audioURL)
            return
        }
        let request = PreviewPipelineRequest(
            sessionID: snapshot.taskID,
            epoch: epoch,
            requestID: UUID(),
            chunkID: snapshot.chunkIndex,
            lane: .correction,
            audioURL: snapshot.audioURL,
            audioRange: snapshot.audioRange,
            boundary: snapshot.boundary,
            enqueuedUptime: ProcessInfo.processInfo.systemUptime
        )
        if let admitted = scheduler.enqueueCorrection(request) {
            execute(admitted)
        }
    }

    func reset() {
        scheduler.reset(epoch: epoch + 1)
    }

    func cancelPending() {
        acceptsNewRequests = false
        stopFinalizationDeadlineWorkItem?.cancel()
        stopFinalizationDeadlineWorkItem = nil
        timeoutWorkItemsByRequestID.values.forEach { $0.cancel() }
        timeoutWorkItemsByRequestID.removeAll()
        let discarded = scheduler.cancelAll()
        for request in discarded {
            try? FileManager.default.removeItem(at: request.audioURL)
        }
        completeStopFinalization()
    }

    func finishWhenCorrectionsDrained(
        tailSnapshot: ExperimentalPreviewTailSnapshot?,
        completion: @escaping (PreviewTranscriptState) -> Void
    ) {
        acceptsNewRequests = false
        for request in scheduler.prepareForCorrectionDrain() {
            try? FileManager.default.removeItem(at: request.audioURL)
        }
        drainCompletion = completion
        scheduleStopFinalizationDeadline()
        if let tailSnapshot {
            tailFinalizationRequest = PreviewPipelineRequest(
                sessionID: tailSnapshot.taskID,
                epoch: epoch,
                requestID: UUID(),
                chunkID: Int.max,
                lane: .stopTail,
                audioURL: tailSnapshot.audioURL,
                audioRange: tailSnapshot.audioRange,
                boundary: nil,
                enqueuedUptime: ProcessInfo.processInfo.systemUptime
            )
        }
        if scheduler.isIdle {
            continueStopFinalizationIfReady()
        }
    }

    private func execute(_ request: PreviewPipelineRequest) {
        let startedUptime = ProcessInfo.processInfo.systemUptime
        let queueMilliseconds = max(0, Int((startedUptime - request.enqueuedUptime) * 1_000))
        let audioMilliseconds = max(0, Int(request.audioRange.duration * 1_000))
        let pendingFast = scheduler.hasPendingFastRequest
        let correctionBacklog = scheduler.pendingCorrectionCount
        LaunchDiagnostics.markAsync(
            "preview_request_start lane=\(request.lane.rawValue) chunk=\(request.chunkID) request_id=\(request.requestID.uuidString.prefix(8)) queue_ms=\(queueMilliseconds) audio_ms=\(audioMilliseconds) pending_fast=\(pendingFast) correction_backlog=\(correctionBacklog)"
        )
        if request.lane == .fast,
           queueMilliseconds > Self.fastQueueBudgetMilliseconds {
            LaunchDiagnostics.markAsync(
                "preview_fast_budget_miss request_id=\(request.requestID.uuidString.prefix(8)) queue_ms=\(queueMilliseconds) budget_ms=\(Self.fastQueueBudgetMilliseconds) correction_backlog=\(correctionBacklog)"
            )
        }
        if correctionBacklog > Self.correctionBacklogWarningThreshold {
            LaunchDiagnostics.markAsync(
                "preview_correction_backlog_warning request_id=\(request.requestID.uuidString.prefix(8)) correction_backlog=\(correctionBacklog) pending_fast=\(pendingFast)"
            )
        }
        scheduleTimeout(for: request, startedUptime: startedUptime, queueMilliseconds: queueMilliseconds, audioMilliseconds: audioMilliseconds)
        transcriber.transcribeDetailed(audio: request.audioURL, configuration: configuration) { [weak self] response in
            let callbackUptime = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                guard let self else {
                    try? FileManager.default.removeItem(at: request.audioURL)
                    return
                }
                let completedUptime = ProcessInfo.processInfo.systemUptime
                let recognitionMilliseconds = max(0, Int((callbackUptime - startedUptime) * 1_000))
                let totalMilliseconds = max(0, Int((completedUptime - request.enqueuedUptime) * 1_000))
                let outcome: String
                switch response {
                case .success:
                    outcome = "success"
                case .failure:
                    outcome = "failure"
                }
                self.cancelTimeout(for: request.requestID)
                LaunchDiagnostics.markAsync(
                    "preview_request_done lane=\(request.lane.rawValue) chunk=\(request.chunkID) request_id=\(request.requestID.uuidString.prefix(8)) outcome=\(outcome) queue_ms=\(queueMilliseconds) recognition_ms=\(recognitionMilliseconds) total_ms=\(totalMilliseconds) audio_ms=\(audioMilliseconds) pending_fast=\(self.scheduler.hasPendingFastRequest) correction_backlog=\(self.scheduler.pendingCorrectionCount)"
                )
                defer {
                    try? FileManager.default.removeItem(at: request.audioURL)
                    if let next = self.scheduler.complete(
                        requestID: request.requestID,
                        completedAt: completedUptime
                    ) {
                        self.execute(next)
                    } else if self.scheduler.isIdle {
                        self.continueStopFinalizationIfReady()
                    }
                }
                // Every callback is admitted by sessionID + epoch + requestID before it can mutate state.
                guard request.sessionID == self.sessionID,
                      request.epoch == self.epoch,
                      self.scheduler.activeRequest?.requestID == request.requestID else { return }
                guard case .success(let nativeResult) = response else {
                    if request.lane != .fast {
                        self.onState(self.reducer.markRecoveryRequested())
                        LaunchDiagnostics.markAsync(
                            "experimental_preview_recovery_requested lane=\(request.lane.rawValue) request_id=\(request.requestID.uuidString.prefix(8))"
                        )
                    }
                    return
                }
                let text = cleanRecognitionText(nativeResult.text, languageMode: self.configuration.languageMode)
                let authority: RealtimeRecognitionHallucinationFilter.Authority
                switch request.lane {
                case .fast:
                    authority = .fast
                case .correction:
                    authority = .correction
                case .stopTail:
                    authority = .stopTail
                }
                switch self.hallucinationFilter.evaluate(
                    text: text,
                    previousPreviewText: self.reducer.state.displayText,
                    authority: authority
                ) {
                case .suppress(let reason):
                    LaunchDiagnostics.markAsync(
                        "realtime_result_suppressed path=overlap lane=\(request.lane.rawValue) reason=\(reason.rawValue)"
                    )
                    return
                case .keep:
                    break
                }
                let result = PreviewRecognitionResult(
                    sessionID: request.sessionID,
                    epoch: request.epoch,
                    requestID: request.requestID,
                    chunkID: request.chunkID,
                    sourceLane: request.lane,
                    audioRange: request.audioRange,
                    text: text,
                    tokens: nativeResult.tokens,
                    tokenTimestamps: nativeResult.validatedTokenTimestamps,
                    boundary: request.boundary
                )
                let event: PreviewTranscriptEvent = request.lane == .fast ? .fast(result) : .correction(result)
                let publishedState = self.reducer.apply(event)
                if let transition = self.reducer.lastOwnershipTransition {
                    self.transcriptTrace.recordMerge(
                        result: result,
                        transition: transition,
                        confirmedCharacterCount: self.reducer.state.confirmedCharacterCount,
                        volatileCharacterCount: self.reducer.state.mutableTailText.count
                    )
                }
                if let state = publishedState {
                    self.onState(state)
                }
            }
        }
    }

    private func scheduleTimeout(
        for request: PreviewPipelineRequest,
        startedUptime: TimeInterval,
        queueMilliseconds: Int,
        audioMilliseconds: Int
    ) {
        let timeout = Self.previewTimeoutSeconds(for: request)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleTimeout(
                    request: request,
                    startedUptime: startedUptime,
                    queueMilliseconds: queueMilliseconds,
                    audioMilliseconds: audioMilliseconds,
                    timeoutSeconds: timeout
                )
            }
        }
        timeoutWorkItemsByRequestID[request.requestID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func cancelTimeout(for requestID: UUID) {
        timeoutWorkItemsByRequestID.removeValue(forKey: requestID)?.cancel()
    }

    private func handleTimeout(
        request: PreviewPipelineRequest,
        startedUptime: TimeInterval,
        queueMilliseconds: Int,
        audioMilliseconds: Int,
        timeoutSeconds: TimeInterval
    ) {
        guard timeoutWorkItemsByRequestID.removeValue(forKey: request.requestID) != nil else { return }
        guard request.sessionID == sessionID,
              request.epoch == epoch,
              scheduler.activeRequest?.requestID == request.requestID else { return }
        let completedUptime = ProcessInfo.processInfo.systemUptime
        let elapsedMilliseconds = max(0, Int((completedUptime - startedUptime) * 1_000))
        LaunchDiagnostics.markAsync(
            "preview_request_timeout lane=\(request.lane.rawValue) chunk=\(request.chunkID) request_id=\(request.requestID.uuidString.prefix(8)) elapsed_ms=\(elapsedMilliseconds) timeout_ms=\(Int(timeoutSeconds * 1_000)) queue_ms=\(queueMilliseconds) audio_ms=\(audioMilliseconds)"
        )
        if request.lane != .fast {
            onState(reducer.markRecoveryRequested())
        }
        try? FileManager.default.removeItem(at: request.audioURL)
        if let next = scheduler.complete(
            requestID: request.requestID,
            completedAt: completedUptime
        ) {
            execute(next)
        } else if scheduler.isIdle {
            continueStopFinalizationIfReady()
        }
    }

    private func removeDiscardedRequests() {
        for request in scheduler.takeDiscardedRequests() {
            try? FileManager.default.removeItem(at: request.audioURL)
        }
    }

    private func continueStopFinalizationIfReady() {
        if let tailFinalizationRequest {
            self.tailFinalizationRequest = nil
            if let admitted = scheduler.beginStopFinalization(tailFinalizationRequest) {
                execute(admitted)
                return
            }
        }
        completeStopFinalization()
    }

    private func scheduleStopFinalizationDeadline() {
        stopFinalizationDeadlineWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleStopFinalizationDeadline()
            }
        }
        stopFinalizationDeadlineWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.stopFinalizationDeadlineSeconds,
            execute: work
        )
    }

    private func handleStopFinalizationDeadline() {
        guard drainCompletion != nil else { return }
        stopFinalizationDeadlineWorkItem = nil
        LaunchDiagnostics.markAsync(
            "preview_stop_tail_timeout session_id=\(sessionID.uuidString.prefix(8)) deadline_ms=\(Int(Self.stopFinalizationDeadlineSeconds * 1_000)) chars=\(reducer.state.displayText.count)"
        )
        onState(reducer.markRecoveryRequested())
        if let tailFinalizationRequest {
            try? FileManager.default.removeItem(at: tailFinalizationRequest.audioURL)
            self.tailFinalizationRequest = nil
        }
        for request in scheduler.cancelAll() {
            cancelTimeout(for: request.requestID)
            try? FileManager.default.removeItem(at: request.audioURL)
        }
        completeStopFinalization()
    }

    private func completeStopFinalization() {
        guard let completion = drainCompletion else { return }
        stopFinalizationDeadlineWorkItem?.cancel()
        stopFinalizationDeadlineWorkItem = nil
        drainCompletion = nil
        completion(reducer.state)
    }
}
