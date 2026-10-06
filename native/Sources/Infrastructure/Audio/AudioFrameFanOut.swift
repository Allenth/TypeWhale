import Foundation

enum AudioFrameFanOutEvent: Sendable {
    case frame(AudioFrame)
    case overflow(droppedFrames: Int)
}

struct AudioFrameFanOutSubscription: Sendable {
    let id: UUID
    let events: AsyncStream<AudioFrameFanOutEvent>
}

/// 单向、非等待、有界的音频帧广播器。
///
/// 任一消费者溢出时只结束该订阅；生产者与其他消费者继续运行。
final class AudioFrameFanOut: @unchecked Sendable {
    private struct Subscriber {
        let continuation: AsyncStream<AudioFrameFanOutEvent>.Continuation
        var droppedFrames: Int
    }

    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]

    var subscriberCount: Int {
        lock.withLock { subscribers.count }
    }

    func isSubscribed(_ id: UUID) -> Bool {
        lock.withLock { subscribers[id] != nil }
    }

    func subscribe(capacity: Int) -> AudioFrameFanOutSubscription {
        let id = UUID()
        var captured: AsyncStream<AudioFrameFanOutEvent>.Continuation?
        let stream = AsyncStream<AudioFrameFanOutEvent>(
            bufferingPolicy: .bufferingNewest(max(1, capacity))
        ) { continuation in
            captured = continuation
        }
        guard let continuation = captured else {
            preconditionFailure("AudioFrameFanOut continuation was not created")
        }
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        lock.withLock {
            subscribers[id] = Subscriber(
                continuation: continuation,
                droppedFrames: 0
            )
        }
        return AudioFrameFanOutSubscription(id: id, events: stream)
    }

    /// 同步非等待 offer；不执行消费者代码，也不在此处做 ASR、磁盘或网络工作。
    func offer(_ frame: AudioFrame) {
        let snapshot = lock.withLock { subscribers }
        var overflowed: [(UUID, Subscriber, Int)] = []
        for (id, subscriber) in snapshot {
            switch subscriber.continuation.yield(.frame(frame)) {
            case .dropped:
                overflowed.append((id, subscriber, subscriber.droppedFrames + 1))
            case .enqueued, .terminated:
                break
            @unknown default:
                break
            }
        }
        for (id, subscriber, droppedFrames) in overflowed {
            guard remove(id) != nil else { continue }
            subscriber.continuation.yield(.overflow(droppedFrames: droppedFrames))
            subscriber.continuation.finish()
        }
    }

    func unsubscribe(_ id: UUID) {
        remove(id)?.continuation.finish()
    }

    func finish() {
        let active = lock.withLock { () -> [Subscriber] in
            let active = Array(subscribers.values)
            subscribers.removeAll(keepingCapacity: false)
            return active
        }
        active.forEach { $0.continuation.finish() }
    }

    @discardableResult
    private func remove(_ id: UUID) -> Subscriber? {
        lock.withLock { subscribers.removeValue(forKey: id) }
    }
}
