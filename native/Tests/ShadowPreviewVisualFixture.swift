import AppKit

@main
enum ShadowPreviewVisualFixture {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { return }

        let presenter = ShadowPreviewPresenter()
        presenter.apply(PreviewViewState(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            providerEpoch: 1,
            sequence: 12,
            stableCharacterCount: 18,
            stableWindowText: "今天我们验证新的旁路预览",
            volatileTailText: "是否稳定",
            lifecycle: .running,
            failure: nil
        ))
        let productionFrame = CGRect(
            x: screen.visibleFrame.midX - 126,
            y: screen.visibleFrame.midY + 48,
            width: 252,
            height: 42
        )
        presenter.show(adjacentTo: productionFrame)

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            presenter.hideImmediately()
            app.terminate(nil)
        }
        app.run()
    }
}
