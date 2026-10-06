import Foundation

/// 主胶囊生产预览状态桥。
///
/// 职责只有一个：把旧实时预览产出的 `PreviewDisplaySnapshot` 转成
/// `PreviewViewState`，供生产主胶囊订阅。它不是旁路/候选诊断 runtime，
/// 也不参与最终粘贴选择。
final class ProductionPreviewStateBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let providerEpoch: Int
    private var sessionID: TranscriptionSessionID?
    private var sequence: UInt64 = 0
    private var latestSnapshot: PreviewDisplaySnapshot?
    private var continuation: AsyncStream<PreviewViewState>.Continuation?
    private var isTerminal = false

    init(providerEpoch: Int = 1) {
        self.providerEpoch = providerEpoch
    }

    func begin(sessionID: TranscriptionSessionID) -> AsyncStream<PreviewViewState> {
        var captured: AsyncStream<PreviewViewState>.Continuation?
        let stream = AsyncStream<PreviewViewState>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            captured = continuation
        }

        lock.lock()
        continuation?.finish()
        self.sessionID = sessionID
        sequence = 0
        latestSnapshot = nil
        continuation = captured
        isTerminal = false
        lock.unlock()

        return stream
    }

    func consume(_ snapshot: PreviewDisplaySnapshot) {
        publish(snapshot: snapshot, lifecycle: .running, shouldFinish: false)
    }

    func complete() {
        publish(snapshot: nil, lifecycle: .completed, shouldFinish: true)
    }

    func cancel() {
        publish(snapshot: nil, lifecycle: .cancelled, shouldFinish: true)
    }

    func end() {
        lock.lock()
        let target = continuation
        continuation = nil
        sessionID = nil
        latestSnapshot = nil
        isTerminal = false
        lock.unlock()
        target?.finish()
    }

    private func publish(
        snapshot incomingSnapshot: PreviewDisplaySnapshot?,
        lifecycle: TranscriptionLifecycle,
        shouldFinish: Bool
    ) {
        let target: AsyncStream<PreviewViewState>.Continuation
        let state: PreviewViewState

        lock.lock()
        guard let sessionID, let continuation, !isTerminal else {
            lock.unlock()
            return
        }
        if let incomingSnapshot {
            latestSnapshot = incomingSnapshot
        }
        let snapshot = incomingSnapshot ?? latestSnapshot ?? .empty
        sequence += 1
        state = PreviewViewState(
            sessionID: sessionID,
            providerEpoch: providerEpoch,
            sequence: sequence,
            stableCharacterCount: snapshot.stableCharacterCount,
            stableWindowText: snapshot.stableWindowText,
            volatileTailText: snapshot.volatileTailText,
            lifecycle: lifecycle,
            failure: nil
        )
        target = continuation
        if shouldFinish {
            isTerminal = true
            self.continuation = nil
            self.sessionID = nil
            latestSnapshot = nil
        }
        lock.unlock()

        target.yield(state)
        if shouldFinish {
            target.finish()
        }
    }
}
