import Foundation

struct PreviewSchedulingPolicy: Equatable, Sendable {
    let fastDeadlineSeconds: TimeInterval
    let maxConsecutiveFastRequests: Int
    let correctionBacklogThreshold: Int
    let backlogMaxConsecutiveFastRequests: Int

    static let testStage = PreviewSchedulingPolicy(
        fastDeadlineSeconds: 0.7,
        maxConsecutiveFastRequests: 4,
        correctionBacklogThreshold: 2,
        backlogMaxConsecutiveFastRequests: 1
    )
}

struct PreviewPipelineRequest: Equatable, Sendable {
    let sessionID: UUID
    let epoch: Int
    let requestID: UUID
    let chunkID: Int
    let lane: PreviewSourceLane
    let audioURL: URL
    let audioRange: PreviewAudioRange
    let boundary: PreviewBoundary?
    let enqueuedUptime: TimeInterval

    init(
        sessionID: UUID,
        epoch: Int,
        requestID: UUID,
        chunkID: Int,
        lane: PreviewSourceLane,
        audioURL: URL,
        audioRange: PreviewAudioRange,
        boundary: PreviewBoundary?,
        enqueuedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.requestID = requestID
        self.chunkID = chunkID
        self.lane = lane
        self.audioURL = audioURL
        self.audioRange = audioRange
        self.boundary = boundary
        self.enqueuedUptime = enqueuedUptime
    }
}

struct PreviewRequestScheduler: Sendable {
    let sessionID: UUID
    private(set) var epoch: Int
    private let policy: PreviewSchedulingPolicy
    private(set) var activeRequest: PreviewPipelineRequest?
    private(set) var pendingFastRequest: PreviewPipelineRequest?
    private var pendingCorrections: [PreviewPipelineRequest] = []
    private var pendingStopTail: PreviewPipelineRequest?
    private var discardedRequests: [PreviewPipelineRequest] = []
    private var lastCompletedLane: PreviewSourceLane?
    private var consecutiveFastCompletions = 0

    var pendingCorrectionCount: Int { pendingCorrections.count }
    var hasPendingFastRequest: Bool { pendingFastRequest != nil }
    var isIdle: Bool { activeRequest == nil }

    init(
        sessionID: UUID,
        epoch: Int,
        policy: PreviewSchedulingPolicy = .testStage
    ) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.policy = policy
    }

    mutating func enqueueFast(_ request: PreviewPipelineRequest) -> PreviewPipelineRequest? {
        guard accepts(request) else { return nil }
        if activeRequest == nil {
            activeRequest = request
            return request
        }
        if let pendingFastRequest {
            discardedRequests.append(pendingFastRequest)
        }
        pendingFastRequest = request
        return nil
    }

    mutating func enqueueCorrection(_ request: PreviewPipelineRequest) -> PreviewPipelineRequest? {
        guard accepts(request) else { return nil }
        if activeRequest == nil {
            activeRequest = request
            return request
        }
        pendingCorrections.append(request)
        return nil
    }

    mutating func beginStopFinalization(_ request: PreviewPipelineRequest) -> PreviewPipelineRequest? {
        guard accepts(request) else { return nil }
        if activeRequest == nil {
            activeRequest = request
            return request
        }
        pendingStopTail = request
        return nil
    }

    mutating func complete(
        requestID: UUID,
        completedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> PreviewPipelineRequest? {
        guard let completedRequest = activeRequest,
              completedRequest.requestID == requestID else { return nil }
        activeRequest = nil
        lastCompletedLane = completedRequest.lane
        if completedRequest.lane == .fast {
            consecutiveFastCompletions += 1
        } else {
            consecutiveFastCompletions = 0
        }
        if let stopTail = pendingStopTail {
            pendingStopTail = nil
            activeRequest = stopTail
        } else if !pendingCorrections.isEmpty,
                  consecutiveFastCompletions >= max(1, policy.maxConsecutiveFastRequests) {
            activeRequest = pendingCorrections.removeFirst()
        } else if !pendingCorrections.isEmpty,
                  pendingCorrections.count >= max(1, policy.correctionBacklogThreshold),
                  consecutiveFastCompletions >= max(1, policy.backlogMaxConsecutiveFastRequests) {
            activeRequest = pendingCorrections.removeFirst()
        } else if let fast = pendingFastRequest,
                  completedAt - fast.enqueuedUptime >= max(0, policy.fastDeadlineSeconds) {
            activeRequest = takePendingFast()
        } else if lastCompletedLane == .correction,
                  pendingFastRequest != nil {
            activeRequest = takePendingFast()
        } else if pendingFastRequest != nil {
            activeRequest = takePendingFast()
        } else if !pendingCorrections.isEmpty {
            activeRequest = pendingCorrections.removeFirst()
        }
        return activeRequest
    }

    mutating func reset(epoch: Int) {
        self.epoch = epoch
        activeRequest = nil
        pendingFastRequest = nil
        pendingCorrections.removeAll(keepingCapacity: true)
        pendingStopTail = nil
        discardedRequests.removeAll(keepingCapacity: true)
        lastCompletedLane = nil
        consecutiveFastCompletions = 0
    }

    mutating func takeDiscardedRequests() -> [PreviewPipelineRequest] {
        defer { discardedRequests.removeAll(keepingCapacity: true) }
        return discardedRequests
    }

    mutating func cancelPending() -> [PreviewPipelineRequest] {
        var discarded: [PreviewPipelineRequest] = []
        if let pendingFastRequest { discarded.append(pendingFastRequest) }
        discarded.append(contentsOf: pendingCorrections)
        if let pendingStopTail { discarded.append(pendingStopTail) }
        pendingFastRequest = nil
        pendingCorrections.removeAll(keepingCapacity: true)
        pendingStopTail = nil
        return discarded
    }

    /// 终止整个 pipeline 时返回活动中及排队中的全部请求，调用方据此清理临时音频。
    mutating func cancelAll() -> [PreviewPipelineRequest] {
        var discarded = cancelPending()
        if let activeRequest {
            discarded.insert(activeRequest, at: 0)
        }
        activeRequest = nil
        return discarded
    }

    mutating func prepareForCorrectionDrain() -> [PreviewPipelineRequest] {
        guard let pendingFastRequest else { return [] }
        self.pendingFastRequest = nil
        return [pendingFastRequest]
    }

    private func accepts(_ request: PreviewPipelineRequest) -> Bool {
        request.sessionID == sessionID && request.epoch == epoch
    }

    private mutating func takePendingFast() -> PreviewPipelineRequest? {
        defer { pendingFastRequest = nil }
        return pendingFastRequest
    }
}
