import AppKit

@MainActor
enum RemoteInspectorSectionFactory {
    static func group(
        title: String,
        body: NSView,
        prominence: InspectorGroupProminence = .standard
    ) -> NSView {
        let stack = NSStackView(views: [inspectorGroupTitleLabel(title), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return inspectorGroupBox(stack, prominence: prominence)
    }

    static func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    static func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}
