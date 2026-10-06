import AppKit

@MainActor
final class ApplicationScopeWindowController: NSWindowController, NSWindowDelegate {
    private enum SavedSizeKey {
        static let width = "applicationScopeWindow.width"
        static let height = "applicationScopeWindow.height"
    }

    let editorModel: ApplicationScopeEditorModel
    let contentContainer = NSView()

    private let cancelCatalogLoading: () -> Void
    private let defaults: UserDefaults
    private let sectionControl = NSSegmentedControl(
        labels: ["整理范围", "自动发送"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let summaryLabel = NSTextField(labelWithString: "")
    private var retainedWhilePresented: ApplicationScopeWindowController?
    private var embeddedContentViewController: NSViewController?
    private var isCompleting = false
    private var sectionDidChange: ((ApplicationScopeSection) -> Void)?

    init(
        editorModel: ApplicationScopeEditorModel,
        cancelCatalogLoading: @escaping () -> Void = {},
        defaults: UserDefaults = .standard
    ) {
        self.editorModel = editorModel
        self.cancelCatalogLoading = cancelCatalogLoading
        self.defaults = defaults

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        super.init(window: window)
        configureWindow(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present(
        in parent: NSWindow,
        sectionDidChange: ((ApplicationScopeSection) -> Void)? = nil
    ) {
        guard let window else { return }
        self.sectionDidChange = sectionDidChange
        retainedWhilePresented = self

        let visibleFrame = parent.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let contentSize = ApplicationScopeWindowSizing.clampedContentSize(
            saved: savedContentSize(),
            visibleFrame: visibleFrame
        )
        window.contentMinSize = ApplicationScopeWindowSizing.clampedContentSize(
            saved: ApplicationScopeWindowSizing.minimumContentSize,
            visibleFrame: visibleFrame
        )
        window.setContentSize(contentSize)
        parent.beginSheet(window)
    }

    func setContentViewController(_ controller: NSViewController) {
        embeddedContentViewController = controller
        let view = controller.view
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    func setSummaryText(_ text: String) {
        summaryLabel.stringValue = text
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveContentSize(window.contentLayoutRect.size)
        cancelCatalogLoading()
        if !isCompleting {
            editorModel.cancel()
        }
        retainedWhilePresented = nil
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "应用范围"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let titleLabel = NSTextField(labelWithString: "应用范围")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitleLabel = NSTextField(
            labelWithString: "为不同应用设置整理方式与粘贴后的发送动作"
        )
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        sectionControl.selectedSegment = editorModel.selectedSection == .rewrite ? 0 : 1
        sectionControl.target = self
        sectionControl.action = #selector(sectionChanged(_:))

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        let header = NSStackView(views: [titleStack, flexibleSpacer(), sectionControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16
        header.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(
            title: "取消",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(
            title: "保存",
            target: self,
            action: #selector(save(_:))
        )
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        let footer = NSStackView(
            views: [summaryLabel, flexibleSpacer(), cancelButton, saveButton]
        )
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(contentContainer)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            contentContainer.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
        ])
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        let section: ApplicationScopeSection = sender.selectedSegment == 1
            ? .autoSend
            : .rewrite
        editorModel.selectedSection = section
        sectionDidChange?(section)
    }

    @objc private func save(_ sender: NSButton) {
        window?.makeFirstResponder(nil)
        editorModel.save()
        finish()
    }

    @objc private func cancel(_ sender: NSButton) {
        editorModel.cancel()
        finish()
    }

    private func finish() {
        guard let window else { return }
        isCompleting = true
        saveContentSize(window.contentLayoutRect.size)
        cancelCatalogLoading()
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
        retainedWhilePresented = nil
    }

    private func savedContentSize() -> NSSize? {
        let width = defaults.double(forKey: SavedSizeKey.width)
        let height = defaults.double(forKey: SavedSizeKey.height)
        guard width > 0, height > 0 else { return nil }
        return NSSize(width: width, height: height)
    }

    private func saveContentSize(_ size: NSSize) {
        defaults.set(size.width, forKey: SavedSizeKey.width)
        defaults.set(size.height, forKey: SavedSizeKey.height)
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
