import Foundation

struct SenseVoiceShadowSchedulingPolicy: Equatable, Sendable {
    let correctionCapacity: Int
    let pendingFastCapacity: Int
    let maxConsecutiveFastBeforeCorrection: Int

    static let initial = SenseVoiceShadowSchedulingPolicy(
        correctionCapacity: 2,
        pendingFastCapacity: 1,
        maxConsecutiveFastBeforeCorrection: 1
    )
}

enum SenseVoiceShadowRequestKind: Equatable, Sendable {
    case fast
    case correction
    case boundaryCorrection
}

struct SenseVoiceShadowRequest: Equatable, Sendable {
    let id: String
    let kind: SenseVoiceShadowRequestKind
    let commitHorizon: Int
    let samples: [Float]
    let sampleRate: Int
    let capturedAtUptime: TimeInterval
    let audioStartTime: TimeInterval
    let audioEndTime: TimeInterval

    init(
        id: String,
        kind: SenseVoiceShadowRequestKind,
        commitHorizon: Int,
        samples: [Float],
        sampleRate: Int,
        capturedAtUptime: TimeInterval,
        audioStartTime: TimeInterval = 0,
        audioEndTime: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.commitHorizon = commitHorizon
        self.samples = samples
        self.sampleRate = sampleRate
        self.capturedAtUptime = capturedAtUptime
        self.audioStartTime = audioStartTime
        self.audioEndTime = audioEndTime ?? (audioStartTime + Double(samples.count) / Double(max(1, sampleRate)))
    }
}

enum SenseVoiceShadowDegradationReason: Equatable, Sendable {
    case correctionCapacityExceeded
}

enum SenseVoiceShadowSchedulerState: Equatable, Sendable {
    case active
    case degraded(SenseVoiceShadowDegradationReason)
}

/// SenseVoice 旁路的纯有界调度器；不持有模型、文件或 UI。
struct SenseVoiceShadowScheduler: Sendable {
    let policy: SenseVoiceShadowSchedulingPolicy
    private(set) var state: SenseVoiceShadowSchedulerState = .active
    private(set) var activeRequest: SenseVoiceShadowRequest?
    private var pendingFast: SenseVoiceShadowRequest?
    private var pendingCorrections: [SenseVoiceShadowRequest] = []
    private var consecutiveFastAdmissions = 0
    private(set) var maximumObservedPendingFast = 0
    private(set) var maximumObservedPendingCorrections = 0
    private(set) var discardedFastRequestCount = 0
    private(set) var discardedCorrectionRequestCount = 0

    init(policy: SenseVoiceShadowSchedulingPolicy) {
        self.policy = policy
    }

    var pendingFastCount: Int { pendingFast == nil ? 0 : 1 }
    var pendingCorrectionCount: Int { pendingCorrections.count }
    var isIdle: Bool {
        activeRequest == nil && pendingFast == nil && pendingCorrections.isEmpty
    }

    mutating func enqueue(_ request: SenseVoiceShadowRequest) -> [SenseVoiceShadowRequest] {
        switch request.kind {
        case .fast:
            let discarded = pendingFast.map { [$0] } ?? []
            discardedFastRequestCount += discarded.count
            pendingFast = request
            maximumObservedPendingFast = max(maximumObservedPendingFast, pendingFastCount)
            return discarded

        case .correction, .boundaryCorrection:
            guard state == .active else {
                discardedCorrectionRequestCount += 1
                return [request]
            }
            let capacity = max(0, policy.correctionCapacity)
            guard capacity > 0 else {
                state = .degraded(.correctionCapacityExceeded)
                discardedCorrectionRequestCount += 1
                return [request]
            }
            if pendingCorrections.count < capacity {
                pendingCorrections.append(request)
                maximumObservedPendingCorrections = max(
                    maximumObservedPendingCorrections,
                    pendingCorrections.count
                )
                return []
            }
            if let index = pendingCorrections.lastIndex(where: {
                $0.commitHorizon == request.commitHorizon
            }) {
                let replaced = pendingCorrections[index]
                pendingCorrections[index] = request
                discardedCorrectionRequestCount += 1
                return [replaced]
            }
            state = .degraded(.correctionCapacityExceeded)
            discardedCorrectionRequestCount += 1
            return [request]
        }
    }

    mutating func enqueueFinalTail(_ request: SenseVoiceShadowRequest) -> [SenseVoiceShadowRequest] {
        var discarded: [SenseVoiceShadowRequest] = []
        if let pendingFast { discarded.append(pendingFast) }
        discarded.append(contentsOf: pendingCorrections)
        if pendingFast != nil { discardedFastRequestCount += 1 }
        discardedCorrectionRequestCount += pendingCorrections.count
        pendingFast = nil
        pendingCorrections = [request]
        state = .active
        maximumObservedPendingCorrections = max(
            maximumObservedPendingCorrections,
            pendingCorrections.count
        )
        return discarded
    }

    mutating func admitNextIfIdle() -> SenseVoiceShadowRequest? {
        guard activeRequest == nil else { return nil }
        activeRequest = takeNext()
        return activeRequest
    }

    mutating func complete(activeRequestID: String) -> SenseVoiceShadowRequest? {
        guard activeRequest?.id == activeRequestID else { return nil }
        activeRequest = nil
        return admitNextIfIdle()
    }

    mutating func cancelAll() -> [SenseVoiceShadowRequest] {
        var cancelled: [SenseVoiceShadowRequest] = []
        if let activeRequest { cancelled.append(activeRequest) }
        if let pendingFast { cancelled.append(pendingFast) }
        cancelled.append(contentsOf: pendingCorrections)
        activeRequest = nil
        pendingFast = nil
        pendingCorrections.removeAll(keepingCapacity: false)
        consecutiveFastAdmissions = 0
        return cancelled
    }

    private mutating func takeNext() -> SenseVoiceShadowRequest? {
        let fastLimit = max(0, policy.maxConsecutiveFastBeforeCorrection)
        if !pendingCorrections.isEmpty,
           (pendingFast == nil || consecutiveFastAdmissions >= fastLimit) {
            consecutiveFastAdmissions = 0
            return pendingCorrections.removeFirst()
        }
        if let pendingFast {
            self.pendingFast = nil
            consecutiveFastAdmissions += 1
            return pendingFast
        }
        if !pendingCorrections.isEmpty {
            consecutiveFastAdmissions = 0
            return pendingCorrections.removeFirst()
        }
        return nil
    }
}
