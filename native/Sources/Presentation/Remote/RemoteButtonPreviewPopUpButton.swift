import AppKit

@MainActor
final class RemoteButtonPreviewPopUpButton: NSPopUpButton {
    let remoteButton: RemoteButton
    var onPreview: ((RemoteButton) -> Void)?

    init(button: RemoteButton) {
        remoteButton = button
        super.init(frame: .zero, pullsDown: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        previewButton()
        super.mouseDown(with: event)
    }

    func previewButton() {
        onPreview?(remoteButton)
    }
}
