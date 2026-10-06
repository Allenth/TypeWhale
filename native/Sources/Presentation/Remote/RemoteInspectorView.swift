import AppKit

@MainActor
final class RemoteInspectorView: NSView {
    var onEnabledChange: ((Bool) -> Void)? {
        didSet { connectionView.onEnabledChange = onEnabledChange }
    }
    var onPrimaryAction: (() -> Void)? {
        didSet { connectionView.onPrimaryAction = onPrimaryAction }
    }
    var onMappingChange: ((RemoteButton, RemoteButtonAction) -> Void)? {
        didSet { mappingView.onMappingChange = onMappingChange }
    }
    var onResetMappings: (() -> Void)? {
        didSet { mappingView.onResetMappings = onResetMappings }
    }

    private let connectionView = RemoteConnectionOverviewView()
    private let pipelineView = RemoteVoicePipelineView()
    private let mappingView = RemoteButtonMappingView()
    private let supportView = RemoteSupportView()
    private let guideView = RemoteButtonGuideView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        mappingView.onButtonPreview = { [weak self] button in
            self?.guideView.preview(button: button)
        }
        let page = FlippedStackView(views: [
            connectionView,
            pipelineView,
            mappingView,
            supportView,
            RemoteInspectorSectionFactory.group(
                title: "设备与按键说明",
                body: guideView
            ),
        ])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = UILayout.groupSpacing
        page.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 10, right: 10)
        for child in page.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        }
        RemoteInspectorSectionFactory.pin(page, to: self)
        apply(snapshot: .initial)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: RemoteInputSnapshot) {
        connectionView.apply(snapshot: snapshot)
        pipelineView.apply(snapshot: snapshot)
        mappingView.apply(mapping: snapshot.mappings)
        supportView.apply(snapshot: snapshot)
        guideView.apply(
            mapping: snapshot.mappings,
            pressedButton: snapshot.pressedButton,
            clearsImmediately: shouldClearPressImmediately(snapshot.phase)
        )
    }

    private func shouldClearPressImmediately(_ phase: RemoteConnectionPhase) -> Bool {
        switch phase {
        case .disabled, .bluetoothUnavailable, .unpaired, .retrying, .protocolFailure:
            return true
        case .scanning, .connecting, .negotiating, .ready, .listening, .processing, .busy:
            return false
        }
    }
}
