import AppKit
import QuartzCore

enum OpenClawReplyStackPolicy {
    struct Item: Equatable {
        let userText: String
        let replyText: String
    }

    static func appending(_ message: String, to existing: [String]) -> [String] {
        existing + [message]
    }

    static func appending(_ item: Item, to existing: [Item]) -> [Item] {
        existing + [item]
    }

    static func removingReply(_ replyText: String, from existing: [Item]) -> [Item] {
        existing.filter { $0.replyText != replyText }
    }
}

enum OpenClawReplyLayoutPolicy {
    struct Layout: Equatable {
        let frame: CGRect
        let requiresScrolling: Bool
    }

    static func layout(
        contentHeight: CGFloat,
        visibleFrame: CGRect,
        width: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        leftMargin: CGFloat
    ) -> Layout {
        let availableHeight = max(64, visibleFrame.height - topMargin - bottomMargin)
        let height = min(max(64, contentHeight), availableHeight)
        let frame = CGRect(
            x: visibleFrame.minX + leftMargin,
            y: visibleFrame.maxY - topMargin - height,
            width: width,
            height: height
        )
        return Layout(
            frame: frame,
            requiresScrolling: contentHeight > availableHeight
        )
    }
}

enum OpenClawReplyDisplayDurationPolicy {
    static let maximum: TimeInterval = 180

    static func resolved(_ requested: TimeInterval?) -> TimeInterval {
        guard let requested, requested.isFinite, requested > 0 else {
            return maximum
        }
        return min(requested, maximum)
    }
}

enum OpenClawReplyLifecyclePolicy {
    enum Action: Equatable {
        case collapseToOrb
        case clearMessages
        case expandMessages
    }

    static let idleTimeoutAction: Action = .collapseToOrb
    static let clearButtonAction: Action = .clearMessages
    static let orbClickAction: Action = .expandMessages
}

enum OpenClawReplyMarkdownRenderer {
    private enum Style {
        static let text = NSColor(calibratedWhite: 1, alpha: 0.95)
        static let baseFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        static let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        static let headingFont = NSFont.systemFont(ofSize: 14, weight: .bold)
        static let monoFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        static let linkText = NSColor(calibratedRed: 0.68, green: 0.88, blue: 1.0, alpha: 0.98)
    }

    static func attributedString(from markdown: String) -> NSAttributedString {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let result = NSMutableAttributedString()
        var index = 0

        while index < lines.count {
            if let tableEnd = markdownTableEnd(startingAt: index, lines: lines) {
                appendTable(Array(lines[index...tableEnd]), to: result)
                index = tableEnd + 1
                continue
            }

            appendLine(lines[index], to: result)
            index += 1
        }

        trimTrailingNewlines(result)
        return result
    }

    private static func appendLine(_ line: String, to result: NSMutableAttributedString) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            result.append(NSAttributedString(string: "\n"))
            return
        }

        if isHorizontalRule(trimmed) {
            appendHorizontalRule(to: result)
            return
        }

        if let heading = headingText(from: trimmed) {
            appendInline(heading, to: result, baseFont: Style.headingFont, color: Style.text)
            result.append(NSAttributedString(string: "\n\n"))
            return
        }

        if let bullet = bulletText(from: trimmed) {
            result.append(NSAttributedString(string: "• ", attributes: attributes(font: Style.boldFont, color: Style.text)))
            appendInline(bullet, to: result, baseFont: Style.baseFont, color: Style.text)
            result.append(NSAttributedString(string: "\n"))
            return
        }

        appendInline(trimmed, to: result, baseFont: Style.baseFont, color: Style.text)
        result.append(NSAttributedString(string: "\n\n"))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func appendHorizontalRule(to result: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .natural
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacingBefore = 2
        paragraph.paragraphSpacing = 6
        result.append(NSAttributedString(
            string: "────────────────────────\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: Style.text.withAlphaComponent(0.72),
                .paragraphStyle: paragraph,
            ]
        ))
    }

    private static func headingText(from line: String) -> String? {
        guard line.first == "#" else { return nil }
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else { return nil }
        let text = line.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func bulletText(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] {
            if line.hasPrefix(marker) { return String(line.dropFirst(marker.count)) }
        }
        if let dot = line.firstIndex(of: ".") {
            let prefix = line[..<dot]
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                let afterDot = line[line.index(after: dot)...]
                if afterDot.first == " " {
                    return String(afterDot.dropFirst())
                }
            }
        }
        return nil
    }

    private static func appendInline(_ text: String, to result: NSMutableAttributedString, baseFont: NSFont, color: NSColor) {
        var cursor = text.startIndex
        var plainStart = cursor

        func appendPlain(from start: String.Index, upTo end: String.Index) {
            guard start < end else { return }
            result.append(NSAttributedString(string: String(text[start..<end]), attributes: attributes(font: baseFont, color: color)))
        }

        while cursor < text.endIndex {
            if text[cursor] == "[",
               let closeBracket = text[cursor..<text.endIndex].firstIndex(of: "]"),
               closeBracket < text.index(before: text.endIndex),
               text[text.index(after: closeBracket)] == "(",
               let closeParen = text[text.index(after: closeBracket)..<text.endIndex].firstIndex(of: ")") {
                let labelStart = text.index(after: cursor)
                let urlStart = text.index(closeBracket, offsetBy: 2)
                let label = String(text[labelStart..<closeBracket])
                let rawURL = String(text[urlStart..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, let url = URL(string: rawURL), Self.isAllowedLinkURL(url) {
                    appendPlain(from: plainStart, upTo: cursor)
                    result.append(NSAttributedString(
                        string: label,
                        attributes: linkAttributes(font: baseFont, url: url)
                    ))
                    cursor = text.index(after: closeParen)
                    plainStart = cursor
                    continue
                }
            }

            if linkPrefix(in: text, at: cursor) != nil {
                let linkEnd = bareLinkEnd(in: text, from: cursor)
                let rawLink = String(text[cursor..<linkEnd])
                let trimmedLink = rawLink.trimmingCharacters(in: trailingLinkPunctuation)
                let trailingCount = rawLink.count - trimmedLink.count
                if let url = URL(string: trimmedLink), Self.isAllowedLinkURL(url) {
                    appendPlain(from: plainStart, upTo: cursor)
                    result.append(NSAttributedString(
                        string: trimmedLink,
                        attributes: linkAttributes(font: baseFont, url: url)
                    ))
                    let trailingStart = text.index(linkEnd, offsetBy: -trailingCount)
                    appendPlain(from: trailingStart, upTo: linkEnd)
                    cursor = linkEnd
                    plainStart = cursor
                    continue
                }
            }

            if text[cursor...].hasPrefix("**"),
               let close = text[text.index(cursor, offsetBy: 2)..<text.endIndex].range(of: "**") {
                let contentStart = text.index(cursor, offsetBy: 2)
                appendPlain(from: plainStart, upTo: cursor)
                result.append(NSAttributedString(
                    string: String(text[contentStart..<close.lowerBound]),
                    attributes: attributes(font: Style.boldFont, color: color)
                ))
                cursor = close.upperBound
                plainStart = cursor
                continue
            }

            if text[cursor] == "`",
               let close = text[text.index(after: cursor)..<text.endIndex].firstIndex(of: "`") {
                appendPlain(from: plainStart, upTo: cursor)
                let codeStart = text.index(after: cursor)
                result.append(NSAttributedString(
                    string: String(text[codeStart..<close]),
                    attributes: attributes(font: Style.monoFont, color: color.withAlphaComponent(0.94))
                ))
                cursor = text.index(after: close)
                plainStart = cursor
                continue
            }

            cursor = text.index(after: cursor)
        }

        appendPlain(from: plainStart, upTo: text.endIndex)
    }

    private static let trailingLinkPunctuation = CharacterSet(charactersIn: ".,;:!?)，。；：！？）")

    private static func linkPrefix(in text: String, at cursor: String.Index) -> String? {
        if text[cursor...].hasPrefix("https://") { return "https://" }
        if text[cursor...].hasPrefix("http://") { return "http://" }
        return nil
    }

    private static func bareLinkEnd(in text: String, from start: String.Index) -> String.Index {
        var end = start
        while end < text.endIndex {
            let character = text[end]
            if character.isWhitespace || character == "<" || character == ">" || character == "\"" {
                break
            }
            end = text.index(after: end)
        }
        return end
    }

    private static func isAllowedLinkURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func markdownTableEnd(startingAt start: Int, lines: [String]) -> Int? {
        guard start + 1 < lines.count,
              tableCells(from: lines[start]).count >= 2,
              isSeparatorRow(lines[start + 1]) else {
            return nil
        }

        var end = start + 1
        while end + 1 < lines.count, tableCells(from: lines[end + 1]).count >= 2 {
            end += 1
        }
        return end
    }

    private static func appendTable(_ lines: [String], to result: NSMutableAttributedString) {
        let rows = lines
            .enumerated()
            .filter { !isSeparatorRow($0.element) }
            .map { tableCells(from: $0.element) }
            .filter { !$0.isEmpty }
        guard let columnCount = rows.map(\.count).max(), columnCount > 0 else { return }

        let widths = (0..<columnCount).map { column in
            rows.map { row in column < row.count ? row[column].count : 0 }.max() ?? 0
        }

        for (rowIndex, row) in rows.enumerated() {
            let line = (0..<columnCount).map { column -> String in
                let value = column < row.count ? row[column] : ""
                return value.padding(toLength: max(widths[column], value.count), withPad: " ", startingAt: 0)
            }.joined(separator: "   ")
            let font = rowIndex == 0 ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold) : Style.monoFont
            result.append(NSAttributedString(string: line + "\n", attributes: attributes(font: font, color: Style.text)))
        }
        result.append(NSAttributedString(string: "\n"))
    }

    private static func tableCells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = tableCells(from: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.8
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    }

    private static func linkAttributes(font: NSFont, url: URL) -> [NSAttributedString.Key: Any] {
        var values = attributes(font: font, color: Style.linkText)
        values[.link] = url
        values[.underlineStyle] = NSUnderlineStyle.single.rawValue
        return values
    }

    private static func trimTrailingNewlines(_ value: NSMutableAttributedString) {
        while value.string.hasSuffix("\n") {
            value.deleteCharacters(in: NSRange(location: value.length - 1, length: 1))
        }
    }
}

private final class OpenClawReplyCloseButton: NSButton {
    let messageID: UUID

    init(messageID: UUID) {
        self.messageID = messageID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class OpenClawReplyCopyButton: NSButton {
    let text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class OpenClawReplyCopyableBubbleView: NSView {
    let text: String
    var onCopy: ((String) -> Void)?

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onCopy?(text)
            return
        }
        super.mouseDown(with: event)
    }
}

private final class OpenClawReplyCopyableTextField: NSTextField {
    let textToCopy: String
    var onCopy: ((String) -> Void)?

    init(attributedString: NSAttributedString, textToCopy: String) {
        self.textToCopy = textToCopy
        super.init(frame: .zero)
        attributedStringValue = attributedString
        isEditable = false
        isBordered = false
        drawsBackground = false
        isSelectable = true
        allowsEditingTextAttributes = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onCopy?(textToCopy)
            return
        }
        super.mouseDown(with: event)
    }
}

private final class OpenClawReplyCloseShadowView: NSView {
    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            ellipseIn: bounds.insetBy(dx: 2, dy: 2),
            transform: nil
        )
    }
}

final class OpenClawReplyAvatarView: NSView {
    enum Role {
        case assistant
        case user
    }

    private let role: Role
    private let pulseLayer = CAShapeLayer()
    private let waveformLayer = CAShapeLayer()
    var isSpeaking = false {
        didSet {
            guard isSpeaking != oldValue else { return }
            needsDisplay = true
            updateSpeakingAnimation()
        }
    }

    init(role: Role, accessibilityIdentifier: String, isSpeaking: Bool = false) {
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        pulseLayer.fillColor = NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.18, alpha: 0.18).cgColor
        pulseLayer.strokeColor = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.30, alpha: 0.65).cgColor
        pulseLayer.lineWidth = 1.2
        pulseLayer.opacity = 0
        waveformLayer.fillColor = nil
        waveformLayer.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.86).cgColor
        waveformLayer.lineWidth = 1.3
        waveformLayer.lineCap = .round
        waveformLayer.opacity = 0
        layer?.addSublayer(pulseLayer)
        layer?.addSublayer(waveformLayer)
        setAccessibilityIdentifier(accessibilityIdentifier)
        translatesAutoresizingMaskIntoConstraints = false
        self.isSpeaking = isSpeaking
        updateSpeakingAnimation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 1, dy: 1)

        switch role {
        case .assistant:
            drawOpenClawBadge(in: rect)
        case .user:
            drawAppIconAvatar(in: rect)
        }
    }

    override func layout() {
        super.layout()
        updateSpeakingLayerPaths()
    }

    private func updateSpeakingLayerPaths() {
        let pulseRect = bounds.insetBy(dx: -4, dy: -4)
        pulseLayer.path = CGPath(ellipseIn: pulseRect, transform: nil)
        let path = CGMutablePath()
        let midY = bounds.midY
        let startX = bounds.minX + bounds.width * 0.25
        let step = bounds.width * 0.10
        path.move(to: CGPoint(x: startX, y: midY))
        path.addLine(to: CGPoint(x: startX + step, y: midY + 3.5))
        path.addLine(to: CGPoint(x: startX + step * 2, y: midY - 3.0))
        path.addLine(to: CGPoint(x: startX + step * 3, y: midY + 4.0))
        path.addLine(to: CGPoint(x: startX + step * 4, y: midY - 2.0))
        path.addLine(to: CGPoint(x: startX + step * 5, y: midY + 2.8))
        waveformLayer.path = path
    }

    private func updateSpeakingAnimation() {
        guard role == .assistant else { return }
        updateSpeakingLayerPaths()
        if isSpeaking {
            pulseLayer.opacity = 1
            waveformLayer.opacity = 1
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.82
            scale.toValue = 1.18
            scale.duration = 0.9
            scale.autoreverses = true
            scale.repeatCount = .infinity
            scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulseLayer.add(scale, forKey: "pulse")

            let wave = CABasicAnimation(keyPath: "strokeEnd")
            wave.fromValue = 0.18
            wave.toValue = 1.0
            wave.duration = 0.72
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            waveformLayer.add(wave, forKey: "waveform")
        } else {
            pulseLayer.removeAllAnimations()
            waveformLayer.removeAllAnimations()
            pulseLayer.opacity = 0
            waveformLayer.opacity = 0
        }
    }

    private func drawOpenClawBadge(in rect: NSRect) {
        let shadow = NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: -1))
        NSColor(calibratedWhite: 0, alpha: 0.28).setFill()
        shadow.fill()

        let badge = NSBezierPath(ovalIn: rect)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.18, green: 0.015, blue: 0.018, alpha: 0.98),
            NSColor(calibratedRed: 0.42, green: 0.02, blue: 0.025, alpha: 0.98),
        ])?.draw(in: badge, angle: -45)
        NSColor(calibratedRed: 1, green: 0.30, blue: 0.22, alpha: 0.78).setStroke()
        badge.lineWidth = 1.1
        badge.stroke()

        drawLobster(in: rect.insetBy(dx: 3.6, dy: 3.4))
    }

    private func drawLobster(in rect: NSRect) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        let highlight = NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.38, alpha: 0.94)
        let main = NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.16, alpha: 1)
        let shadow = NSColor(calibratedRed: 0.70, green: 0.045, blue: 0.05, alpha: 1)

        let leftClaw = NSBezierPath()
        leftClaw.move(to: point(0.20, 0.55))
        leftClaw.curve(to: point(0.08, 0.34), controlPoint1: point(0.02, 0.56), controlPoint2: point(-0.01, 0.42))
        leftClaw.curve(to: point(0.30, 0.35), controlPoint1: point(0.17, 0.21), controlPoint2: point(0.30, 0.25))
        leftClaw.curve(to: point(0.20, 0.55), controlPoint1: point(0.37, 0.47), controlPoint2: point(0.31, 0.57))

        let rightClaw = NSBezierPath()
        rightClaw.move(to: point(0.80, 0.55))
        rightClaw.curve(to: point(0.92, 0.34), controlPoint1: point(0.98, 0.56), controlPoint2: point(1.01, 0.42))
        rightClaw.curve(to: point(0.70, 0.35), controlPoint1: point(0.83, 0.21), controlPoint2: point(0.70, 0.25))
        rightClaw.curve(to: point(0.80, 0.55), controlPoint1: point(0.63, 0.47), controlPoint2: point(0.69, 0.57))

        let body = NSBezierPath()
        body.move(to: point(0.50, 0.93))
        body.curve(to: point(0.21, 0.48), controlPoint1: point(0.28, 0.92), controlPoint2: point(0.17, 0.73))
        body.curve(to: point(0.41, 0.16), controlPoint1: point(0.24, 0.30), controlPoint2: point(0.33, 0.20))
        body.line(to: point(0.41, 0.02))
        body.line(to: point(0.49, 0.02))
        body.line(to: point(0.50, 0.15))
        body.line(to: point(0.56, 0.02))
        body.line(to: point(0.64, 0.02))
        body.line(to: point(0.61, 0.16))
        body.curve(to: point(0.79, 0.48), controlPoint1: point(0.70, 0.21), controlPoint2: point(0.76, 0.31))
        body.curve(to: point(0.50, 0.93), controlPoint1: point(0.83, 0.73), controlPoint2: point(0.72, 0.92))
        body.close()

        [leftClaw, rightClaw, body].forEach { path in
            NSGradient(colors: [highlight, main, shadow])?.draw(in: path, angle: -65)
            NSColor(calibratedRed: 1, green: 0.58, blue: 0.48, alpha: 0.38).setStroke()
            path.lineWidth = 0.55
            path.stroke()
        }

        let antennaLeft = NSBezierPath()
        antennaLeft.move(to: point(0.42, 0.87))
        antennaLeft.curve(to: point(0.18, 0.96), controlPoint1: point(0.35, 1.02), controlPoint2: point(0.27, 1.04))
        let antennaRight = NSBezierPath()
        antennaRight.move(to: point(0.58, 0.87))
        antennaRight.curve(to: point(0.82, 0.96), controlPoint1: point(0.65, 1.02), controlPoint2: point(0.73, 1.04))
        main.setStroke()
        [antennaLeft, antennaRight].forEach {
            $0.lineWidth = 0.95
            $0.lineCapStyle = .round
            $0.stroke()
        }

        NSColor(calibratedWhite: 0.03, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point(0.36, 0.69).x - 1.45, y: point(0.36, 0.69).y - 1.45, width: 2.9, height: 2.9)).fill()
        NSBezierPath(ovalIn: NSRect(x: point(0.64, 0.69).x - 1.45, y: point(0.64, 0.69).y - 1.45, width: 2.9, height: 2.9)).fill()
        NSColor(calibratedRed: 0.0, green: 0.90, blue: 0.80, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point(0.37, 0.70).x - 0.55, y: point(0.37, 0.70).y - 0.55, width: 1.1, height: 1.1)).fill()
        NSBezierPath(ovalIn: NSRect(x: point(0.65, 0.70).x - 0.55, y: point(0.65, 0.70).y - 0.55, width: 1.1, height: 1.1)).fill()
    }

    private func drawAppIconAvatar(in rect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: -1)).fill()

        let circle = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        if let icon = appIconImage() {
            icon.draw(in: rect, from: visibleContentRect(for: icon), operation: .sourceOver, fraction: 1)
        } else {
            drawFallbackAppIcon(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1, alpha: 0.65).setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }

    private func visibleContentRect(for image: NSImage) -> NSRect {
        let size = image.size
        let pixelsWide = max(1, Int(ceil(size.width)))
        let pixelsHigh = max(1, Int(ceil(size.height)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSRect(origin: .zero, size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixelsWide
        var minY = pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.05 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: CGFloat(minX) / CGFloat(pixelsWide) * size.width,
            y: CGFloat(minY) / CGFloat(pixelsHigh) * size.height,
            width: CGFloat(maxX - minX + 1) / CGFloat(pixelsWide) * size.width,
            height: CGFloat(maxY - minY + 1) / CGFloat(pixelsHigh) * size.height
        )
    }

    private func appIconImage() -> NSImage? {
        if let icon = NSApp.applicationIconImage, icon.isValid {
            return icon
        }
        if let icon = NSImage(named: NSImage.applicationIconName), icon.isValid {
            return icon
        }
        let bundlePath = Bundle.main.bundlePath
        let workspaceIcon = NSWorkspace.shared.icon(forFile: bundlePath)
        return workspaceIcon.isValid ? workspaceIcon : nil
    }

    private func drawFallbackAppIcon(in rect: NSRect) {
        NSGradient(colors: [
            NSColor(calibratedRed: 0.20, green: 0.36, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1),
        ])?.draw(in: NSBezierPath(ovalIn: rect), angle: -45)

        let whale = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.20, dy: rect.height * 0.30), xRadius: rect.width * 0.14, yRadius: rect.height * 0.14)
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
        whale.fill()
    }
}

@MainActor
final class OpenClawReplyPresenter {
    static let shared = OpenClawReplyPresenter()
    nonisolated static let defaultDisplayDuration: TimeInterval? = nil
    nonisolated static let maximumDisplayDuration: TimeInterval = OpenClawReplyDisplayDurationPolicy.maximum
    nonisolated static let newMessageRevealDelay: TimeInterval = 0.5
    nonisolated static let newMessageFadeDuration: TimeInterval = 0.18
    nonisolated static let displayEventPlaybackDelay: TimeInterval = 0.45
    nonisolated static let scrollsDuringRevealAnimation = false
    nonisolated static let collapsesToOrbAfterIdle = true

    private enum Metrics {
        static let width: CGFloat = 430
        static let inset: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let topMargin: CGFloat = 24
        static let bottomMargin: CGFloat = 18
        static let leftMargin: CGFloat = 24
        static let closeButtonSize: CGFloat = 22
        static let avatarSize: CGFloat = 28
        static let orbSize: CGFloat = 42
        static let rowGap: CGFloat = 10
        static let bubblePaddingX: CGFloat = 12
        static let bubblePaddingY: CGFloat = 9
        static let clearButtonTopPadding: CGFloat = 26
    }

    private enum BubblePalette {
        static let userBackground = NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.28, alpha: 0.94)
        static let userBorder = NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.70, alpha: 0.70)
        static let assistantBackground = NSColor(calibratedRed: 0.44, green: 0.025, blue: 0.034, alpha: 0.94)
        static let assistantBorder = NSColor(calibratedRed: 1.00, green: 0.33, blue: 0.25, alpha: 0.68)
        static let statusBackground = NSColor(calibratedRed: 0.38, green: 0.040, blue: 0.034, alpha: 0.92)
        static let statusBorder = NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.28, alpha: 0.58)
    }

    private enum MessageRole {
        case user
        case assistant
        case status
        case loading
    }

    private struct Message: Identifiable {
        let id: UUID
        let turnID: UUID
        let role: MessageRole
        let text: String
        let createdAt: Date
        let displayDuration: TimeInterval
    }

    private let panel: NSPanel
    private let messageContainer = NSView()
    private let background = NSView()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let clearButton = NSButton(title: "清空", target: nil, action: nil)
    private let stopVoiceButton = NSButton(title: "停止", target: nil, action: nil)
    private let voiceToggleButton = NSButton(title: "朗读", target: nil, action: nil)
    private let collapseButton = NSButton(title: "收起", target: nil, action: nil)
    private let orbButton = NSButton(title: "", target: nil, action: nil)
    private var messages: [Message] = []
    private var dismissWorkItem: DispatchWorkItem?
    private var revealWorkItems: [UUID: DispatchWorkItem] = [:]
    private var pendingRevealIDs: [UUID] = []
    private var revealQueueWorkItem: DispatchWorkItem?
    private var visibilityRetryWorkItem: DispatchWorkItem?
    private var revealedMessageIDs = Set<UUID>()
    private var loadingMessageIDsByTurn: [UUID: UUID] = [:]
    private var replaceableStatusMessageIDsByTurn: [UUID: UUID] = [:]
    private var sequenceWorkItemsByTurn: [UUID: [DispatchWorkItem]] = [:]
    private var latestMessageToKeepVisible: UUID?
    private var isCollapsedToOrb = false
    private var isOpenClawSpeaking = false
    private var voicePlaybackObservers: [NSObjectProtocol] = []
    private let fadeDuration: TimeInterval = 0.16
    private static let legacyTurnID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.alphaValue = 0

        messageContainer.translatesAutoresizingMaskIntoConstraints = false
        messageContainer.wantsLayer = true
        messageContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.15, alpha: 0.34).cgColor
        messageContainer.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        messageContainer.layer?.borderWidth = 1
        messageContainer.layer?.cornerRadius = 16
        messageContainer.layer?.masksToBounds = false
        messageContainer.layer?.shadowColor = NSColor.black.cgColor
        messageContainer.layer?.shadowOpacity = 0.18
        messageContainer.layer?.shadowRadius = 8
        messageContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        messageContainer.setAccessibilityIdentifier("openclaw-reply-message-container")

        background.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setAccessibilityIdentifier("openclaw-reply-scroll-container")

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.target = self
        clearButton.action = #selector(clearMessagesFromButton(_:))
        clearButton.isBordered = false
        clearButton.controlSize = .small
        clearButton.font = .systemFont(ofSize: 11, weight: .semibold)
        clearButton.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.94)
        clearButton.attributedTitle = NSAttributedString(
            string: "清空",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
            ]
        )
        clearButton.wantsLayer = true
        clearButton.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.40, alpha: 0.96).cgColor
        clearButton.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        clearButton.layer?.borderWidth = 1
        clearButton.layer?.cornerRadius = 7
        clearButton.layer?.masksToBounds = false
        clearButton.layer?.shadowColor = NSColor.black.cgColor
        clearButton.layer?.shadowOpacity = 0.22
        clearButton.layer?.shadowRadius = 3
        clearButton.layer?.shadowOffset = NSSize(width: 0, height: -1)
        clearButton.isHidden = true
        clearButton.toolTip = "清空 OpenClaw 消息"
        clearButton.setAccessibilityIdentifier("openclaw-reply-clear-button")

        configureControlButton(voiceToggleButton, title: "朗读", width: 62)
        voiceToggleButton.target = self
        voiceToggleButton.action = #selector(toggleVoicePlayback(_:))
        voiceToggleButton.toolTip = "开启或关闭 OpenClaw 自动朗读"
        voiceToggleButton.setAccessibilityIdentifier("openclaw-reply-voice-toggle-button")
        voiceToggleButton.isHidden = true
        refreshVoiceToggleButton()

        configureControlButton(stopVoiceButton, title: "停止", width: 48)
        stopVoiceButton.target = self
        stopVoiceButton.action = #selector(stopVoicePlayback(_:))
        stopVoiceButton.toolTip = "停止当前 OpenClaw 朗读"
        stopVoiceButton.setAccessibilityIdentifier("openclaw-reply-stop-voice-button")
        stopVoiceButton.isHidden = true

        configureControlButton(collapseButton, title: "收起", width: 48)
        collapseButton.target = self
        collapseButton.action = #selector(collapseFromButton(_:))
        collapseButton.toolTip = "收起为小龙虾圆球"
        collapseButton.setAccessibilityIdentifier("openclaw-reply-collapse-button")
        collapseButton.isHidden = true

        configureOrbButton()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(messageContainer)
        content.addSubview(clearButton)
        content.addSubview(voiceToggleButton)
        content.addSubview(stopVoiceButton)
        content.addSubview(collapseButton)
        content.addSubview(orbButton)
        messageContainer.addSubview(scrollView)
        background.addSubview(stack)
        scrollView.documentView = background
        NSLayoutConstraint.activate([
            messageContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            messageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            messageContainer.topAnchor.constraint(equalTo: content.topAnchor),
            messageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: messageContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: messageContainer.bottomAnchor),
            background.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Metrics.inset),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Metrics.inset),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: Metrics.inset + Metrics.clearButtonTopPadding),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Metrics.inset),
            voiceToggleButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            voiceToggleButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.inset),
            stopVoiceButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            stopVoiceButton.leadingAnchor.constraint(equalTo: voiceToggleButton.trailingAnchor, constant: 7),
            collapseButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            collapseButton.leadingAnchor.constraint(equalTo: stopVoiceButton.trailingAnchor, constant: 7),
            clearButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            clearButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.inset),
            clearButton.widthAnchor.constraint(equalToConstant: 48),
            clearButton.heightAnchor.constraint(equalToConstant: 24),
            orbButton.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            orbButton.topAnchor.constraint(equalTo: content.topAnchor),
            orbButton.widthAnchor.constraint(equalToConstant: Metrics.orbSize),
            orbButton.heightAnchor.constraint(equalToConstant: Metrics.orbSize),
        ])
        panel.contentView = content
        observeVoicePlayback()
    }

    private func configureControlButton(_ button: NSButton, title: String, width: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.94)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.40, alpha: 0.96).cgColor
        button.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = false
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.22
        button.layer?.shadowRadius = 3
        button.layer?.shadowOffset = NSSize(width: 0, height: -1)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        setControlButtonTitle(button, title)
    }

    private func setControlButtonTitle(_ button: NSButton, _ title: String) {
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
            ]
        )
    }

    private func configureOrbButton() {
        orbButton.translatesAutoresizingMaskIntoConstraints = false
        orbButton.isBordered = false
        orbButton.wantsLayer = true
        orbButton.layer?.backgroundColor = NSColor.clear.cgColor
        orbButton.target = self
        orbButton.action = #selector(expandFromOrbButton(_:))
        orbButton.toolTip = "展开 OpenClaw 消息"
        orbButton.setAccessibilityIdentifier("openclaw-reply-orb-button")
        orbButton.isHidden = true

        let avatar = OpenClawReplyAvatarView(role: .assistant, accessibilityIdentifier: "openclaw-reply-orb-avatar")
        orbButton.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.centerXAnchor.constraint(equalTo: orbButton.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: orbButton.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: Metrics.orbSize - 4),
            avatar.heightAnchor.constraint(equalToConstant: Metrics.orbSize - 4),
        ])
    }

    func showReply(_ reply: String, duration: TimeInterval? = defaultDisplayDuration, turnID: UUID? = nil) {
        let resolvedTurnID = resolveTurnID(turnID)
        cancelReplySequence(for: resolvedTurnID)
        let replacesLoading = removeLoadingMessage(for: resolvedTurnID, renderAfterRemoval: false)
        appendMessage(role: .assistant, text: reply, duration: duration, revealImmediately: replacesLoading, turnID: resolvedTurnID)
    }

    @discardableResult
    func showUserMessage(_ text: String, duration: TimeInterval? = defaultDisplayDuration, turnID: UUID? = nil) -> UUID {
        let resolvedTurnID = resolveTurnID(turnID)
        cancelReplySequence(for: resolvedTurnID)
        appendMessage(role: .user, text: text, duration: duration, turnID: resolvedTurnID)
        return resolvedTurnID
    }

    func showStatusMessage(_ text: String, duration: TimeInterval? = defaultDisplayDuration, turnID: UUID? = nil) {
        let resolvedTurnID = resolveTurnID(turnID)
        let replacesLoading = removeLoadingMessage(for: resolvedTurnID, renderAfterRemoval: false)
        if Self.isReplaceableWaitingStatus(text) {
            removeReplaceableStatusMessage(for: resolvedTurnID, renderAfterRemoval: false)
        }
        if let messageID = appendMessage(role: .status, text: text, duration: duration, revealImmediately: replacesLoading, turnID: resolvedTurnID),
           Self.isReplaceableWaitingStatus(text) {
            replaceableStatusMessageIDsByTurn[resolvedTurnID] = messageID
        }
    }

    func showStatusMessages(_ messages: [String], duration: TimeInterval? = defaultDisplayDuration, turnID: UUID? = nil) {
        let resolvedTurnID = resolveTurnID(turnID)
        let replacesLoading: Bool
        if !messages.isEmpty {
            replacesLoading = removeLoadingMessage(for: resolvedTurnID, renderAfterRemoval: false)
        } else {
            replacesLoading = false
        }
        for (index, message) in messages.enumerated() {
            appendMessage(
                role: .status,
                text: message,
                duration: duration,
                revealImmediately: replacesLoading && index == 0,
                turnID: resolvedTurnID
            )
        }
    }

    func showReplySequence(displayEvents: [String], reply: String, duration: TimeInterval? = defaultDisplayDuration, turnID: UUID? = nil) {
        let resolvedTurnID = resolveTurnID(turnID)
        cancelReplySequence(for: resolvedTurnID)
        let events = displayEvents
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !Self.isCompletionOnlyDisplayEvent($0) }
        let finalReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !events.isEmpty else {
            showReply(finalReply, duration: duration, turnID: resolvedTurnID)
            return
        }
        replayDisplayEvents(events, index: 0, finalReply: finalReply, duration: duration, turnID: resolvedTurnID)
    }

    func showReplyLoading(turnID: UUID? = nil) {
        showReplyLoading(turnID: turnID, revealImmediately: false)
    }

    private func showReplyLoading(turnID: UUID?, revealImmediately: Bool) {
        let resolvedTurnID = resolveTurnID(turnID)
        if let loadingMessageID = loadingMessageIDsByTurn[resolvedTurnID],
           messages.contains(where: { $0.id == loadingMessageID }) {
            return
        }
        let replacesWaitingStatus = removeReplaceableStatusMessage(for: resolvedTurnID, renderAfterRemoval: false)
        loadingMessageIDsByTurn[resolvedTurnID] = nil
        appendMessage(
            role: .loading,
            text: "OpenClaw 正在回复",
            duration: nil,
            revealImmediately: revealImmediately || replacesWaitingStatus,
            turnID: resolvedTurnID,
            preserveScrollPosition: replacesWaitingStatus
        )
    }

    func hideReplyLoading(turnID: UUID? = nil) {
        removeLoadingMessage(for: resolveTurnID(turnID), renderAfterRemoval: true)
    }

    private func cancelReplySequence(for turnID: UUID) {
        sequenceWorkItemsByTurn.removeValue(forKey: turnID)?.forEach { $0.cancel() }
    }

    private func replayDisplayEvents(_ events: [String], index: Int, finalReply: String, duration: TimeInterval?, turnID: UUID) {
        guard index < events.count else {
            showReply(finalReply, duration: duration, turnID: turnID)
            return
        }
        showStatusMessage(events[index], duration: duration, turnID: turnID)
        showReplyLoading(turnID: turnID, revealImmediately: true)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.replayDisplayEvents(events, index: index + 1, finalReply: finalReply, duration: duration, turnID: turnID)
            }
        }
        sequenceWorkItemsByTurn[turnID, default: []].append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayEventPlaybackDelay, execute: work)
    }

    func showConversation(userText: String, replyText: String, duration: TimeInterval? = defaultDisplayDuration) {
        let turnID = UUID()
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty || !reply.isEmpty else { return }

        if !user.isEmpty {
            appendMessage(role: .user, text: user, duration: duration, turnID: turnID)
        }
        if !reply.isEmpty {
            let replacesLoading = removeLoadingMessage(for: turnID, renderAfterRemoval: false)
            appendMessage(role: .assistant, text: reply, duration: duration, revealImmediately: replacesLoading, turnID: turnID)
        }
    }

    private func resolveTurnID(_ turnID: UUID?) -> UUID {
        turnID ?? Self.legacyTurnID
    }

    private func observeVoicePlayback() {
        let center = NotificationCenter.default
        voicePlaybackObservers.append(center.addObserver(
            forName: OpenClawVoicePlaybackNotification.didStartSpeaking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setOpenClawSpeaking(true)
            }
        })
        voicePlaybackObservers.append(center.addObserver(
            forName: OpenClawVoicePlaybackNotification.didStopSpeaking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setOpenClawSpeaking(false)
            }
        })
    }

    private func setOpenClawSpeaking(_ isSpeaking: Bool) {
        guard isOpenClawSpeaking != isSpeaking else { return }
        isOpenClawSpeaking = isSpeaking
        guard !messages.isEmpty else { return }
        render(preservedScrollOrigin: scrollView.contentView.bounds.origin)
        showPanel()
    }

    private static func isCompletionOnlyDisplayEvent(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ".", with: "")
        return normalized == "completed"
            || normalized == "complete"
            || normalized == "done"
            || normalized == "完成"
            || normalized == "已完成"
            || normalized == "openclaw 已完成"
    }

    private static func isReplaceableWaitingStatus(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("已排队")
            || normalized.contains("等待 OpenClaw 回复")
            || normalized.contains("等待 OpenClaw")
    }

    @discardableResult
    private func appendMessage(
        role: MessageRole,
        text: String,
        duration: TimeInterval?,
        revealImmediately: Bool = false,
        turnID: UUID,
        preserveScrollPosition: Bool = false
    ) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let message = Message(
            id: UUID(),
            turnID: turnID,
            role: role,
            text: trimmed,
            createdAt: Date(),
            displayDuration: OpenClawReplyDisplayDurationPolicy.resolved(duration)
        )
        if let lastTurnIndex = messages.lastIndex(where: { $0.turnID == turnID }) {
            messages.insert(message, at: messages.index(after: lastTurnIndex))
        } else {
            messages.append(message)
        }
        if revealImmediately {
            revealedMessageIDs.insert(message.id)
        }
        if role == .loading {
            loadingMessageIDsByTurn[turnID] = message.id
        }
        latestMessageToKeepVisible = message.id
        if isCollapsedToOrb {
            isCollapsedToOrb = false
            orbButton.isHidden = true
            messageContainer.isHidden = false
        }
        let preservedScrollOrigin = preserveScrollPosition ? scrollView.contentView.bounds.origin : nil
        render(focusMessageID: message.id, preservedScrollOrigin: preservedScrollOrigin)
        showPanel()
        if !revealImmediately {
            scheduleReveal(for: message.id)
        }
        restartWindowDismissTimer(after: message.displayDuration)
        return message.id
    }

    private func removeMessage(id: UUID) {
        let removedTurnID = messages.first(where: { $0.id == id })?.turnID
        cancelReveal(for: id)
        revealedMessageIDs.remove(id)
        if let removedTurnID, loadingMessageIDsByTurn[removedTurnID] == id {
            loadingMessageIDsByTurn[removedTurnID] = nil
        }
        if let removedTurnID, replaceableStatusMessageIDsByTurn[removedTurnID] == id {
            replaceableStatusMessageIDsByTurn[removedTurnID] = nil
        }
        messages.removeAll { $0.id == id }
        guard !messages.isEmpty else {
            cancelWindowDismissTimer()
            hidePanel()
            return
        }
        render()
        showPanel()
    }

    @discardableResult
    private func removeLoadingMessage(for turnID: UUID, renderAfterRemoval: Bool) -> Bool {
        guard let id = loadingMessageIDsByTurn[turnID] else { return false }
        cancelReveal(for: id)
        revealedMessageIDs.remove(id)
        loadingMessageIDsByTurn[turnID] = nil
        messages.removeAll { $0.id == id }
        guard renderAfterRemoval else { return true }
        guard !messages.isEmpty else {
            cancelWindowDismissTimer()
            hidePanel()
            return true
        }
        render()
        showPanel()
        return true
    }

    @discardableResult
    private func removeReplaceableStatusMessage(for turnID: UUID, renderAfterRemoval: Bool) -> Bool {
        guard let id = replaceableStatusMessageIDsByTurn[turnID] else { return false }
        cancelReveal(for: id)
        revealedMessageIDs.remove(id)
        replaceableStatusMessageIDsByTurn[turnID] = nil
        messages.removeAll { $0.id == id }
        guard renderAfterRemoval else { return true }
        guard !messages.isEmpty else {
            cancelWindowDismissTimer()
            hidePanel()
            return true
        }
        render()
        showPanel()
        return true
    }

    private func render(focusMessageID: UUID? = nil, preservedScrollOrigin: NSPoint? = nil) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for message in messages {
            stack.addArrangedSubview(makeCard(for: message))
        }
        let hasMessages = !messages.isEmpty
        messageContainer.isHidden = isCollapsedToOrb || !hasMessages
        orbButton.isHidden = !isCollapsedToOrb
        clearButton.isHidden = isCollapsedToOrb || !hasMessages
        stopVoiceButton.isHidden = isCollapsedToOrb || !hasMessages
        voiceToggleButton.isHidden = isCollapsedToOrb || !hasMessages
        collapseButton.isHidden = isCollapsedToOrb || !hasMessages
        refreshVoiceToggleButton()
        panel.contentView?.layoutSubtreeIfNeeded()
        resizeAndPosition()
        guard !isCollapsedToOrb else { return }
        if let preservedScrollOrigin {
            scrollToPreservedOrigin(preservedScrollOrigin)
        } else {
            keepLatestMessageVisible(focusMessageID ?? latestMessageToKeepVisible ?? messages.last?.id, retryAfterLayout: true)
        }
    }

    private func restartWindowDismissTimer(after duration: TimeInterval) {
        cancelWindowDismissTimer()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.collapseToOrb()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelWindowDismissTimer() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func scheduleReveal(for id: UUID) {
        guard !revealedMessageIDs.contains(id), revealWorkItems[id] == nil else { return }
        pendingRevealIDs.append(id)
        revealWorkItems[id] = DispatchWorkItem {}
        scheduleNextQueuedReveal(restartDelay: true)
    }

    private func cancelReveal(for id: UUID) {
        revealWorkItems.removeValue(forKey: id)?.cancel()
        pendingRevealIDs.removeAll { $0 == id }
        if pendingRevealIDs.isEmpty {
            revealQueueWorkItem?.cancel()
            revealQueueWorkItem = nil
        }
    }

    private func scheduleNextQueuedReveal(restartDelay: Bool) {
        guard !pendingRevealIDs.isEmpty else {
            revealQueueWorkItem?.cancel()
            revealQueueWorkItem = nil
            return
        }
        if restartDelay {
            revealQueueWorkItem?.cancel()
            revealQueueWorkItem = nil
        } else if revealQueueWorkItem != nil {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.revealNextQueuedMessage()
            }
        }
        revealQueueWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.newMessageRevealDelay, execute: work)
    }

    private func revealNextQueuedMessage() {
        revealQueueWorkItem = nil
        while !pendingRevealIDs.isEmpty {
            let id = pendingRevealIDs.removeFirst()
            guard revealWorkItems[id] != nil else { continue }
            revealMessage(id: id)
            break
        }
        scheduleNextQueuedReveal(restartDelay: false)
    }

    private func revealMessage(id: UUID) {
        revealWorkItems.removeValue(forKey: id)?.cancel()
        guard messages.contains(where: { $0.id == id }) else { return }
        revealedMessageIDs.insert(id)
        guard let card = findCardView(id: id) else {
            render()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.newMessageFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().alphaValue = 1
        }
    }

    private func findCardView(id: UUID) -> NSView? {
        findCardView(in: panel.contentView, identifier: NSUserInterfaceItemIdentifier(id.uuidString))
    }

    private func findCardView(in view: NSView?, identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        guard let view else { return nil }
        if view.identifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findCardView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    private func makeCard(for message: Message) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.clear.cgColor
        card.layer?.borderWidth = 0
        card.identifier = NSUserInterfaceItemIdentifier(message.id.uuidString)
        card.alphaValue = revealedMessageIDs.contains(message.id) ? 1 : 0
        card.translatesAutoresizingMaskIntoConstraints = false

        let bodyWidth = Metrics.width - Metrics.inset * 2 - Metrics.cardPadding * 2
        let bubbleMaxWidth = bodyWidth - Metrics.avatarSize - Metrics.rowGap - 36
        let contentViews: [NSView]
        switch message.role {
        case .user:
            card.setAccessibilityIdentifier("openclaw-reply-user-card")
            card.setAccessibilityLabel("我的 OpenClaw 消息")
            contentViews = [
                userChatRow(
                    text: message.text,
                    createdAt: message.createdAt,
                    width: bodyWidth,
                    bubbleMaxWidth: bubbleMaxWidth,
                    messageID: message.id
                )
            ]
        case .assistant:
            card.setAccessibilityIdentifier("openclaw-reply-assistant-card")
            card.setAccessibilityLabel("OpenClaw 回复")
            contentViews = [
                assistantChatRow(
                    text: message.text,
                    createdAt: message.createdAt,
                    width: bodyWidth,
                    bubbleMaxWidth: bubbleMaxWidth,
                    messageID: message.id
                )
            ]
        case .status:
            card.setAccessibilityIdentifier("openclaw-reply-status-card")
            card.setAccessibilityLabel("OpenClaw 状态")
            contentViews = [
                statusChatRow(
                    text: message.text,
                    createdAt: message.createdAt,
                    width: bodyWidth,
                    bubbleMaxWidth: bubbleMaxWidth,
                    messageID: message.id
                )
            ]
        case .loading:
            card.setAccessibilityIdentifier("openclaw-reply-loading-card")
            card.setAccessibilityLabel("OpenClaw 正在回复")
            contentViews = [
                loadingChatRow(
                    createdAt: message.createdAt,
                    width: bodyWidth,
                    bubbleMaxWidth: bubbleMaxWidth,
                    messageID: message.id
                )
            ]
        }

        let content = NSStackView(views: contentViews)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(content)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: Metrics.width - Metrics.inset * 2),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Metrics.cardPadding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Metrics.cardPadding),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
        ])
        return card
    }

    private func userChatRow(text: String, createdAt: Date, width: CGFloat, bubbleMaxWidth: CGFloat, messageID: UUID) -> NSView {
        let avatar = OpenClawReplyAvatarView(role: .user, accessibilityIdentifier: "openclaw-reply-user-avatar")
        avatar.widthAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        let body = messageBodyWithTimestamp(
            body: userBodyView(text: text, width: bubbleMaxWidth - Metrics.bubblePaddingX * 2),
            createdAt: createdAt,
            alignment: .left
        )

        let bubble = textBubbleView(
            accessibilityIdentifier: "openclaw-reply-user-bubble",
            backgroundColor: BubblePalette.userBackground,
            borderColor: BubblePalette.userBorder,
            content: body,
            copyText: text
        )
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true

        let closeButton = closeButtonSlot(messageID: messageID, tooltip: "关闭这条我的消息")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer, closeButton, bubble, avatar])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setAccessibilityIdentifier("openclaw-reply-user-row")
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func assistantChatRow(text: String, createdAt: Date, width: CGFloat, bubbleMaxWidth: CGFloat, messageID: UUID) -> NSView {
        let replyBubbleMaxWidth = max(180, bubbleMaxWidth - Metrics.closeButtonSize - 7)
        let avatar = OpenClawReplyAvatarView(
            role: .assistant,
            accessibilityIdentifier: "openclaw-reply-assistant-avatar",
            isSpeaking: isOpenClawSpeaking
        )
        avatar.widthAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        let body = messageBodyWithTimestamp(
            body: replyBodyView(text: text, width: replyBubbleMaxWidth - Metrics.bubblePaddingX * 2),
            createdAt: createdAt,
            alignment: .left
        )

        let bubble = textBubbleView(
            accessibilityIdentifier: "openclaw-reply-assistant-bubble",
            backgroundColor: BubblePalette.assistantBackground,
            borderColor: BubblePalette.assistantBorder,
            content: body,
            copyText: text
        )
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: replyBubbleMaxWidth).isActive = true

        let copyButton = makeCopyButton(text: text)
        let closeButton = closeButtonSlot(messageID: messageID, tooltip: "关闭这条 OpenClaw 回复")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [avatar, bubble, copyButton, closeButton, spacer])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setAccessibilityIdentifier("openclaw-reply-assistant-row")
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func statusChatRow(text: String, createdAt: Date, width: CGFloat, bubbleMaxWidth: CGFloat, messageID: UUID) -> NSView {
        let avatar = OpenClawReplyAvatarView(
            role: .assistant,
            accessibilityIdentifier: "openclaw-reply-status-avatar",
            isSpeaking: isOpenClawSpeaking
        )
        avatar.widthAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        let body = messageBodyWithTimestamp(
            body: statusBodyView(text: text, width: bubbleMaxWidth - Metrics.bubblePaddingX * 2),
            createdAt: createdAt,
            alignment: .left
        )

        let bubble = textBubbleView(
            accessibilityIdentifier: "openclaw-reply-status-bubble",
            backgroundColor: BubblePalette.statusBackground,
            borderColor: BubblePalette.statusBorder,
            content: body,
            copyText: text
        )
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true

        let closeButton = closeButtonSlot(messageID: messageID, tooltip: "关闭这条 OpenClaw 状态")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [avatar, bubble, closeButton, spacer])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setAccessibilityIdentifier("openclaw-reply-status-row")
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func loadingChatRow(createdAt: Date, width: CGFloat, bubbleMaxWidth: CGFloat, messageID: UUID) -> NSView {
        let avatar = OpenClawReplyAvatarView(
            role: .assistant,
            accessibilityIdentifier: "openclaw-reply-loading-avatar",
            isSpeaking: isOpenClawSpeaking
        )
        avatar.widthAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: Metrics.avatarSize).isActive = true
        let body = messageBodyWithTimestamp(
            body: loadingBodyView(width: bubbleMaxWidth - Metrics.bubblePaddingX * 2),
            createdAt: createdAt,
            alignment: .left
        )

        let bubble = textBubbleView(
            accessibilityIdentifier: "openclaw-reply-loading-bubble",
            backgroundColor: BubblePalette.assistantBackground,
            borderColor: BubblePalette.assistantBorder,
            content: body
        )
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true

        let closeButton = closeButtonSlot(messageID: messageID, tooltip: "关闭 OpenClaw 等待状态")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [avatar, bubble, closeButton, spacer])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setAccessibilityIdentifier("openclaw-reply-loading-row")
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func closeButtonSlot(messageID: UUID, tooltip: String) -> NSView {
        let slot = OpenClawReplyCloseShadowView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.wantsLayer = true
        slot.layer?.masksToBounds = false
        slot.layer?.shadowColor = NSColor.black.cgColor
        slot.layer?.shadowOpacity = 0.56
        slot.layer?.shadowRadius = 4.5
        slot.layer?.shadowOffset = .zero
        slot.setAccessibilityIdentifier("openclaw-reply-close-shadow")
        let button = makeCloseButton(messageID: messageID, tooltip: tooltip)
        slot.addSubview(button)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: Metrics.closeButtonSize),
            slot.heightAnchor.constraint(equalToConstant: Metrics.avatarSize),
            button.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])
        return slot
    }

    private func makeCloseButton(messageID: UUID, tooltip: String) -> OpenClawReplyCloseButton {
        let closeButton = OpenClawReplyCloseButton(messageID: messageID)
        if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭") {
            closeButton.image = image
            closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            closeButton.imagePosition = .imageOnly
        } else {
            closeButton.title = "×"
            closeButton.font = .systemFont(ofSize: 18, weight: .bold)
        }
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeMessage(_:))
        closeButton.toolTip = tooltip
        closeButton.setAccessibilityIdentifier("openclaw-reply-close-button")
        closeButton.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        closeButton.wantsLayer = true
        closeButton.layer?.masksToBounds = false
        closeButton.layer?.shadowColor = NSColor.black.cgColor
        closeButton.layer?.shadowOpacity = 0.56
        closeButton.layer?.shadowRadius = 4.5
        closeButton.layer?.shadowOffset = .zero
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: Metrics.closeButtonSize).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: Metrics.closeButtonSize).isActive = true
        return closeButton
    }

    private func makeCopyButton(text: String) -> OpenClawReplyCopyButton {
        let copyButton = OpenClawReplyCopyButton(text: text)
        if let image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "复制") {
            copyButton.image = image
            copyButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
            copyButton.imagePosition = .imageOnly
        } else {
            copyButton.title = "复制"
            copyButton.font = .systemFont(ofSize: 10.5, weight: .semibold)
        }
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyMessage(_:))
        copyButton.toolTip = "复制这条 OpenClaw 回复"
        copyButton.setAccessibilityIdentifier("openclaw-reply-copy-button")
        copyButton.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.40, alpha: 0.96).cgColor
        copyButton.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.20).cgColor
        copyButton.layer?.borderWidth = 1
        copyButton.layer?.cornerRadius = 7
        copyButton.layer?.masksToBounds = false
        copyButton.layer?.shadowColor = NSColor.black.cgColor
        copyButton.layer?.shadowOpacity = 0.28
        copyButton.layer?.shadowRadius = 3
        copyButton.layer?.shadowOffset = NSSize(width: 0, height: -1)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.widthAnchor.constraint(equalToConstant: Metrics.closeButtonSize).isActive = true
        copyButton.heightAnchor.constraint(equalToConstant: Metrics.closeButtonSize).isActive = true
        return copyButton
    }

    private func textBubbleView(
        accessibilityIdentifier: String,
        backgroundColor: NSColor,
        borderColor: NSColor,
        content: NSView,
        copyText: String? = nil
    ) -> NSView {
        let bubble: NSView
        if let copyText {
            let copyableBubble = OpenClawReplyCopyableBubbleView(text: copyText)
            copyableBubble.onCopy = { [weak self] text in
                self?.copyTextToPasteboard(text)
            }
            bubble = copyableBubble
        } else {
            bubble = NSView()
        }
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 10
        bubble.layer?.backgroundColor = backgroundColor.cgColor
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = borderColor.cgColor
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.setAccessibilityIdentifier(accessibilityIdentifier)
        bubble.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: Metrics.bubblePaddingX),
            content.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -Metrics.bubblePaddingX),
            content.topAnchor.constraint(equalTo: bubble.topAnchor, constant: Metrics.bubblePaddingY),
            content.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -Metrics.bubblePaddingY),
        ])
        return bubble
    }

    private func messageBodyWithTimestamp(body: NSView, createdAt: Date, alignment: NSTextAlignment) -> NSView {
        let timestamp = NSTextField(labelWithString: Self.timeFormatter.string(from: createdAt))
        timestamp.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        timestamp.textColor = NSColor(calibratedWhite: 1, alpha: 0.68)
        timestamp.alignment = alignment
        timestamp.maximumNumberOfLines = 1
        timestamp.lineBreakMode = .byClipping
        timestamp.setAccessibilityIdentifier("openclaw-reply-timestamp")
        timestamp.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [timestamp, body])
        stack.orientation = .vertical
        stack.alignment = alignment == .right ? .trailing : .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func userBodyView(text: String, width: CGFloat) -> NSView {
        let user = NSTextField(labelWithString: String(text.prefix(260)))
        user.font = .systemFont(ofSize: 12.5, weight: .medium)
        user.textColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        user.alignment = .left
        user.maximumNumberOfLines = 0
        user.lineBreakMode = .byCharWrapping
        user.preferredMaxLayoutWidth = width
        user.translatesAutoresizingMaskIntoConstraints = false
        user.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return user
    }

    private func loadingBodyView(width: CGFloat) -> NSView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = true
        spinner.setAccessibilityIdentifier("openclaw-reply-loading-spinner")
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 14).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 14).isActive = true
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "OpenClaw 正在回复")
        label.font = .systemFont(ofSize: 12.2, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [spinner, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return row
    }

    private func statusBodyView(text: String, width: CGFloat) -> NSView {
        let status = NSTextField(labelWithString: String(text.prefix(220)))
        status.font = .systemFont(ofSize: 12.2, weight: .semibold)
        status.textColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        status.maximumNumberOfLines = 3
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = width
        status.translatesAutoresizingMaskIntoConstraints = false
        status.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return status
    }

    private func replyBodyView(text: String, width: CGFloat) -> NSView {
        let copyText = String(text.prefix(4000))
        let attributed = OpenClawReplyMarkdownRenderer.attributedString(from: copyText)
        let body = OpenClawReplyCopyableTextField(attributedString: attributed, textToCopy: text)
        body.onCopy = { [weak self] text in
            self?.copyTextToPasteboard(text)
        }
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.preferredMaxLayoutWidth = width
        body.translatesAutoresizingMaskIntoConstraints = false
        body.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return body
    }

    @objc private func closeMessage(_ sender: NSButton) {
        guard let button = sender as? OpenClawReplyCloseButton else { return }
        removeMessage(id: button.messageID)
    }

    @objc private func copyMessage(_ sender: NSButton) {
        guard let button = sender as? OpenClawReplyCopyButton else { return }
        copyTextToPasteboard(button.text)
    }

    private func copyTextToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastPresenter.shared.show("复制成功", style: .success, duration: 1.2)
    }

    @objc private func stopVoicePlayback(_ sender: NSButton) {
        OpenClawVoicePlayer.shared.stop()
        setOpenClawSpeaking(false)
        ToastPresenter.shared.show("已停止朗读", style: .info, duration: 1.2)
    }

    @objc private func toggleVoicePlayback(_ sender: NSButton) {
        var settings = OpenClawVoiceSettingsStore.standard.load()
        settings.enabled.toggle()
        OpenClawVoiceSettingsStore.standard.save(settings)
        if !settings.enabled {
            OpenClawVoicePlayer.shared.stop()
            setOpenClawSpeaking(false)
        }
        refreshVoiceToggleButton()
        ToastPresenter.shared.show(settings.enabled ? "已开启朗读" : "已关闭朗读", style: .info, duration: 1.2)
    }

    @objc private func expandFromOrbButton(_ sender: NSButton) {
        expandFromOrb()
    }

    @objc private func collapseFromButton(_ sender: NSButton) {
        collapseToOrb()
    }

    private func refreshVoiceToggleButton() {
        let enabled = OpenClawVoiceSettingsStore.standard.load().enabled
        setControlButtonTitle(voiceToggleButton, enabled ? "朗读开" : "朗读关")
        voiceToggleButton.layer?.backgroundColor = (enabled
            ? NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.40, alpha: 0.96)
            : NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.22, alpha: 0.92)
        ).cgColor
    }

    @objc private func clearMessagesFromButton(_ sender: NSButton) {
        clearMessages()
    }

    func clearMessages() {
        cancelWindowDismissTimer()
        revealWorkItems.values.forEach { $0.cancel() }
        revealWorkItems.removeAll()
        pendingRevealIDs.removeAll()
        revealQueueWorkItem?.cancel()
        revealQueueWorkItem = nil
        visibilityRetryWorkItem?.cancel()
        visibilityRetryWorkItem = nil
        sequenceWorkItemsByTurn.values.flatMap { $0 }.forEach { $0.cancel() }
        sequenceWorkItemsByTurn.removeAll()
        revealedMessageIDs.removeAll()
        loadingMessageIDsByTurn.removeAll()
        replaceableStatusMessageIDsByTurn.removeAll()
        messages.removeAll()
        isCollapsedToOrb = false
        clearButton.isHidden = true
        stopVoiceButton.isHidden = true
        voiceToggleButton.isHidden = true
        collapseButton.isHidden = true
        orbButton.isHidden = true
        messageContainer.isHidden = false
        latestMessageToKeepVisible = nil
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        hidePanel()
    }

    private func collapseToOrb() {
        guard !messages.isEmpty else {
            hidePanel()
            return
        }
        isCollapsedToOrb = true
        messageContainer.isHidden = true
        clearButton.isHidden = true
        stopVoiceButton.isHidden = true
        voiceToggleButton.isHidden = true
        collapseButton.isHidden = true
        orbButton.isHidden = false
        resizeAndPosition()
        showPanel()
    }

    private func expandFromOrb() {
        guard isCollapsedToOrb else { return }
        isCollapsedToOrb = false
        orbButton.isHidden = true
        messageContainer.isHidden = false
        render(focusMessageID: latestMessageToKeepVisible ?? messages.last?.id)
        showPanel()
    }

    private func showPanel() {
        let shouldFadeIn = !panel.isVisible
        if shouldFadeIn { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)
            }
        }
    }

    private func resizeAndPosition() {
        if isCollapsedToOrb {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let size = NSSize(width: Metrics.orbSize, height: Metrics.orbSize)
            guard let frame = screen?.visibleFrame else {
                panel.setContentSize(size)
                return
            }
            panel.setFrame(
                NSRect(
                    x: frame.minX + Metrics.leftMargin,
                    y: frame.maxY - Metrics.topMargin - Metrics.orbSize,
                    width: Metrics.orbSize,
                    height: Metrics.orbSize
                ),
                display: true
            )
            return
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(stack.fittingSize.height + Metrics.inset * 2 + Metrics.clearButtonTopPadding)
        let contentHeight = max(64, fittingHeight)
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            let size = NSSize(width: Metrics.width, height: contentHeight)
            panel.setContentSize(size)
            background.frame = NSRect(origin: .zero, size: size)
            return
        }
        let layout = OpenClawReplyLayoutPolicy.layout(
            contentHeight: contentHeight,
            visibleFrame: frame,
            width: Metrics.width,
            topMargin: Metrics.topMargin,
            bottomMargin: Metrics.bottomMargin,
            leftMargin: Metrics.leftMargin
        )
        panel.setFrame(layout.frame, display: true)
        background.frame = NSRect(x: 0, y: 0, width: Metrics.width, height: contentHeight)
        scrollView.hasVerticalScroller = layout.requiresScrolling
    }

    private func keepLatestMessageVisible(_ messageID: UUID?, retryAfterLayout: Bool) {
        panel.contentView?.layoutSubtreeIfNeeded()
        if let messageID, let card = findCardView(id: messageID) {
            if card.bounds.height > scrollView.contentView.bounds.height {
                scrollToTop(of: card)
            } else {
                scrollToBottom(of: card)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            scrollToDocumentBottom()
        }

        guard retryAfterLayout else { return }
        visibilityRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.visibilityRetryWorkItem = nil
                self?.keepLatestMessageVisible(messageID, retryAfterLayout: false)
            }
        }
        visibilityRetryWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func scrollToDocumentBottom() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let visibleHeight = scrollView.contentView.bounds.height
        guard documentHeight > visibleHeight else { return }
        let origin = NSPoint(x: 0, y: max(0, documentHeight - visibleHeight))
        scrollContentView(to: origin)
    }

    private func scrollToPreservedOrigin(_ origin: NSPoint) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let visibleHeight = scrollView.contentView.bounds.height
        let maxOriginY = max(0, documentHeight - visibleHeight)
        let preserved = NSPoint(
            x: origin.x,
            y: min(max(0, origin.y), maxOriginY)
        )
        scrollContentView(to: preserved)
    }

    private func scrollToTop(of card: NSView) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else { return }
        let targetVisibleMinY = max(card.bounds.minY, card.bounds.maxY - visibleHeight)
        let deltaY = targetVisibleMinY - card.visibleRect.minY
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxOriginY = max(0, documentHeight - visibleHeight)
        let currentOrigin = scrollView.contentView.bounds.origin
        let targetOriginY = min(max(0, currentOrigin.y + deltaY), maxOriginY)
        scrollContentView(to: NSPoint(x: currentOrigin.x, y: targetOriginY))
    }

    private func scrollToBottom(of card: NSView) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else { return }
        let targetVisibleMinY = card.bounds.minY - Metrics.inset
        let deltaY = targetVisibleMinY - card.visibleRect.minY
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxOriginY = max(0, documentHeight - visibleHeight)
        let currentOrigin = scrollView.contentView.bounds.origin
        let targetOriginY = min(max(0, currentOrigin.y + deltaY), maxOriginY)
        scrollContentView(to: NSPoint(x: currentOrigin.x, y: targetOriginY))
    }

    private func scrollContentView(to origin: NSPoint) {
        let current = scrollView.contentView.bounds.origin
        guard abs(current.x - origin.x) > 0.5 || abs(current.y - origin.y) > 0.5 else {
            return
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
