import Foundation

private func request(
    _ id: String,
    kind: SenseVoiceShadowRequestKind,
    horizon: Int
) -> SenseVoiceShadowRequest {
    SenseVoiceShadowRequest(
        id: id,
        kind: kind,
        commitHorizon: horizon,
        samples: [0.1],
        sampleRate: 16_000,
        capturedAtUptime: 0
    )
}

var scheduler = SenseVoiceShadowScheduler(policy: .initial)
precondition(scheduler.policy.correctionCapacity == 2)
precondition(scheduler.policy.pendingFastCapacity == 1)
precondition(scheduler.policy.maxConsecutiveFastBeforeCorrection == 1)

// 同一时刻只允许一个模型请求进入 active admission slot。
precondition(scheduler.enqueue(request("f0", kind: .fast, horizon: 0)).isEmpty)
precondition(scheduler.admitNextIfIdle()?.id == "f0")
precondition(scheduler.admitNextIfIdle() == nil)

// fast 始终 latest-only；旧 pending 必须被替换并返回给调用方释放。
precondition(scheduler.enqueue(request("f1", kind: .fast, horizon: 0)).isEmpty)
let discardedFast = scheduler.enqueue(request("f2", kind: .fast, horizon: 0))
precondition(discardedFast.map(\.id) == ["f1"])
precondition(scheduler.discardedFastRequestCount == 1)
precondition(scheduler.pendingFastCount == 1)

// correction 容量固定为 2；同一 commit horizon 的更新可以原位替换。
precondition(scheduler.enqueue(request("c0", kind: .correction, horizon: 0)).isEmpty)
precondition(scheduler.enqueue(request("c1", kind: .correction, horizon: 0)).isEmpty)
let replacedCorrection = scheduler.enqueue(request("c2", kind: .correction, horizon: 0))
precondition(replacedCorrection.map(\.id) == ["c1"])
precondition(scheduler.discardedCorrectionRequestCount == 1)
precondition(scheduler.pendingCorrectionCount == 2)
precondition(scheduler.state == .active)

// 容量已满且 commit horizon 前进时不得吞掉旧边界，必须降级并停止新 correction。
let rejected = scheduler.enqueue(request("c3", kind: .correction, horizon: 1))
precondition(rejected.map(\.id) == ["c3"])
precondition(scheduler.discardedCorrectionRequestCount == 2)
precondition(scheduler.state == .degraded(.correctionCapacityExceeded))
precondition(scheduler.pendingCorrectionCount == 2)
let rejectedAfterDegrade = scheduler.enqueue(request("c4", kind: .correction, horizon: 1))
precondition(rejectedAfterDegrade.map(\.id) == ["c4"])

// 压力下最多连续一个 fast，之后必须让 correction 获得 admission。
precondition(scheduler.complete(activeRequestID: "f0")?.kind == .correction)
precondition(scheduler.complete(activeRequestID: "c0")?.id == "f2")
precondition(scheduler.maximumObservedPendingFast == 1)
precondition(scheduler.maximumObservedPendingCorrections == 2)

let cancelled = scheduler.cancelAll()
precondition(cancelled.count == 2)
precondition(scheduler.activeRequest == nil)
precondition(scheduler.pendingFastCount == 0)
precondition(scheduler.pendingCorrectionCount == 0)

print("SenseVoiceShadowSchedulerCheck passed")
