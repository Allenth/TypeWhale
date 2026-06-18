import AppKit

extension NSView {
    func pinEdges(to view: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset),
        ])
    }
}

@MainActor
func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
    let value = NSTextField(labelWithString: text)
    value.translatesAutoresizingMaskIntoConstraints = false
    value.font = .systemFont(ofSize: size, weight: weight)
    value.textColor = .labelColor
    value.alignment = .left
    value.baseWritingDirection = .leftToRight
    value.lineBreakMode = .byWordWrapping
    value.maximumNumberOfLines = 0
    return value
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}
