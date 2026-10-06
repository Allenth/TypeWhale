import Foundation

@main
struct ProductionPreviewSinkRebindingCheck {
    @MainActor
    static func main() async {
        let firstSink = RecordingSink()
        let secondSink = RecordingSink()
        let coordinator = ProductionPreviewTextCoordinator(sink: firstSink)
        var continuation: AsyncStream<PreviewViewState>.Continuation?
        let stream = AsyncStream<PreviewViewState> { continuation = $0 }

        coordinator.replaceSink(secondSink)
        coordinator.begin(states: stream, deliversText: true)
        continuation?.yield(PreviewViewState(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1,
            sequence: 1,
            stableCharacterCount: 5,
            stableWindowText: "第三主题收到",
            volatileTailText: "文字",
            lifecycle: .running,
            failure: nil
        ))

        await waitUntil {
            secondSink.snapshots.last?.displayText == "第三主题收到文字"
        }
        precondition(firstSink.snapshots.isEmpty, "replaced sink must not receive new preview text")
        coordinator.end()
        continuation?.finish()

        var hiddenContinuation: AsyncStream<PreviewViewState>.Continuation?
        let hiddenStream = AsyncStream<PreviewViewState> { hiddenContinuation = $0 }
        coordinator.begin(states: hiddenStream, deliversText: false)
        hiddenContinuation?.yield(PreviewViewState(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1,
            sequence: 1,
            stableCharacterCount: 4,
            stableWindowText: "主窗口继续",
            volatileTailText: "更新",
            lifecycle: .running,
            failure: nil
        ))
        for _ in 0..<50 {
            await Task.yield()
        }
        precondition(
            secondSink.snapshots.count == 1,
            "disabled capsule text delivery must not hide the capsule or forward transcript text"
        )
        coordinator.end()
        hiddenContinuation?.finish()
        print("ProductionPreviewSinkRebindingCheck passed")
    }

    @MainActor
    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        condition: @escaping () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            precondition(
                DispatchTime.now().uptimeNanoseconds < deadline,
                "timed out waiting for rebound preview sink"
            )
            await Task.yield()
        }
    }
}

@MainActor
private final class RecordingSink: ProductionPreviewTextSink {
    private(set) var snapshots: [PreviewDisplaySnapshot] = []

    func updateDraft(_ snapshot: PreviewDisplaySnapshot) {
        snapshots.append(snapshot)
    }
}
