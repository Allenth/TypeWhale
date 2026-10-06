import AppKit

@main
@MainActor
struct ShadowPreviewLifecycleCheck {
    static func main() async {
        let presenter = FakeShadowPreviewPresenter()
        let coordinator = ShadowPreviewCoordinator(presenter: presenter)
        var renderDiagnostics: [(UInt64, Int)] = []
        coordinator.onRenderDiagnostics = { state, drawMilliseconds in
            renderDiagnostics.append((state.sequence, drawMilliseconds))
        }
        let pair = AsyncStream<PreviewViewState>.makeStream()
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let otherSessionID = TranscriptionSessionID(rawValue: UUID())
        let productionFrame = CGRect(x: 500, y: 100, width: 200, height: 42)

        coordinator.begin(states: pair.stream) { productionFrame }
        pair.continuation.yield(state(sessionID: sessionID, sequence: 1, text: "第一条"))
        await waitUntil { presenter.applied.count == 1 }
        precondition(presenter.applied.first?.sessionID == sessionID)
        precondition(presenter.shownFrames == [productionFrame])
        precondition(renderDiagnostics.count == 1)
        precondition(renderDiagnostics[0].0 == 1)
        precondition(renderDiagnostics[0].1 >= 0)

        pair.continuation.yield(state(sessionID: otherSessionID, sequence: 2, text: "其他会话"))
        for _ in 0..<20 { await Task.yield() }
        precondition(presenter.applied.count == 1, "mismatched session must be ignored")

        coordinator.end()
        precondition(presenter.hideCount == 1)
        pair.continuation.yield(state(sessionID: sessionID, sequence: 3, text: "结束后晚到"))
        for _ in 0..<20 { await Task.yield() }
        precondition(presenter.applied.count == 1, "end must cancel subscription")

        print("ShadowPreviewLifecycleCheck passed")
    }

    private static func state(
        sessionID: TranscriptionSessionID,
        sequence: UInt64,
        text: String
    ) -> PreviewViewState {
        PreviewViewState(
            sessionID: sessionID,
            providerEpoch: 1,
            sequence: sequence,
            stableCharacterCount: 0,
            stableWindowText: "",
            volatileTailText: text,
            lifecycle: .running,
            failure: nil
        )
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for shadow preview update")
    }
}

@MainActor
private final class FakeShadowPreviewPresenter: ShadowPreviewPresenting {
    private(set) var applied: [PreviewViewState] = []
    private(set) var shownFrames: [CGRect] = []
    private(set) var hideCount = 0

    func apply(_ state: PreviewViewState) {
        applied.append(state)
    }

    func show(adjacentTo productionFrame: CGRect) {
        shownFrames.append(productionFrame)
    }

    func hideImmediately() {
        hideCount += 1
    }
}
