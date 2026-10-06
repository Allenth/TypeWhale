import AppKit

@MainActor
protocol ShadowPreviewPresenting: AnyObject {
    func apply(_ state: PreviewViewState)
    func show(adjacentTo productionFrame: CGRect)
    func hideImmediately()
}

@MainActor
final class ShadowPreviewCoordinator {
    var onRenderDiagnostics: ((PreviewViewState, Int) -> Void)?
    private let presenter: any ShadowPreviewPresenting
    private var subscriptionTask: Task<Void, Never>?
    private var expectedSessionID: TranscriptionSessionID?
    private var settingObserver: NSObjectProtocol?

    init(presenter: any ShadowPreviewPresenting) {
        self.presenter = presenter
        settingObserver = NotificationCenter.default.addObserver(
            forName: .shadowPreviewSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.object as? Bool, !enabled else { return }
            Task { @MainActor [weak self] in self?.end() }
        }
    }

    deinit {
        subscriptionTask?.cancel()
        if let settingObserver {
            NotificationCenter.default.removeObserver(settingObserver)
        }
    }

    func begin(
        states: AsyncStream<PreviewViewState>,
        productionFrame: @escaping @MainActor () -> CGRect?
    ) {
        subscriptionTask?.cancel()
        expectedSessionID = nil
        subscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in states {
                guard !Task.isCancelled else { return }
                if expectedSessionID == nil {
                    expectedSessionID = state.sessionID
                }
                guard state.sessionID == expectedSessionID else { continue }
                let renderStarted = ProcessInfo.processInfo.systemUptime
                presenter.apply(state)
                if let frame = productionFrame() {
                    presenter.show(adjacentTo: frame)
                }
                let drawMilliseconds = max(
                    0,
                    Int((ProcessInfo.processInfo.systemUptime - renderStarted) * 1_000)
                )
                onRenderDiagnostics?(state, drawMilliseconds)
            }
        }
    }

    func end() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        expectedSessionID = nil
        presenter.hideImmediately()
    }
}
