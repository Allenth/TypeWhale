import AppKit

@MainActor
final class RemoteControlIllustrationView: NSView {
    private let imageProvider: () -> NSImage?
    private var releaseWorkItem: DispatchWorkItem?

    private(set) var activeFeedbackButton: RemoteButton?

    var showsConnectors = true {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        imageProvider = { RemoteControlPhotoResource.image }
        super.init(frame: frameRect)
        configureView()
    }

    init(frame frameRect: NSRect, imageProvider: @escaping () -> NSImage?) {
        self.imageProvider = imageProvider
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let photoRect = XiaomiRemote2ProDiagramSpec.bodyRect(in: bounds)
        if let image = imageProvider() {
            drawPhoto(image, in: photoRect)
            drawPressFeedback(in: photoRect)
        } else {
            drawMissingPhotoPlaceholder(in: photoRect)
        }
        drawConnectors(in: photoRect)
    }

    private func configureView() {
        setAccessibilityElement(false)
        wantsLayer = true
    }

    func setPressedButton(
        _ button: RemoteButton?,
        clearsImmediately: Bool = false
    ) {
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
        if let button {
            activeFeedbackButton = button
            needsDisplay = true
            return
        }
        guard activeFeedbackButton != nil else { return }
        if clearsImmediately {
            activeFeedbackButton = nil
            needsDisplay = true
            return
        }
        let expectedButton = activeFeedbackButton
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeFeedbackButton == expectedButton else { return }
            self.activeFeedbackButton = nil
            self.releaseWorkItem = nil
            self.needsDisplay = true
        }
        releaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RemoteButtonPressVisualSpec.minimumVisibleReleaseDelay,
            execute: workItem
        )
    }

    private func drawPhoto(_ image: NSImage, in photoRect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else {
            drawMissingPhotoPlaceholder(in: photoRect)
            return
        }

        let scale = max(
            photoRect.width / image.size.width,
            photoRect.height / image.size.height
        )
        let renderedSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let renderedRect = CGRect(
            x: photoRect.midX - renderedSize.width / 2,
            y: photoRect.midY - renderedSize.height / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: photoRect, xRadius: 24, yRadius: 24).addClip()
        image.draw(
            in: renderedRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMissingPhotoPlaceholder(in photoRect: CGRect) {
        let path = NSBezierPath(roundedRect: photoRect, xRadius: 24, yRadius: 24)
        UITheme.panelFill.setFill()
        path.fill()
        UITheme.hairline.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1
        path.stroke()

        let message = NSString(string: "遥控器图片不可用")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UITheme.waterInkMuted,
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(
            at: CGPoint(x: photoRect.midX - size.width / 2, y: photoRect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawPressFeedback(in photoRect: CGRect) {
        guard let button = activeFeedbackButton,
              let region = RemoteButtonPressVisualSpec.region(for: button) else { return }
        let rect = region.rect(in: photoRect)
        let path: NSBezierPath
        switch region.shape {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .roundedRect(let radius):
            let corner = min(rect.width, rect.height) * radius
            path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        }

        NSGraphicsContext.saveGraphicsState()
        NSColor.systemBlue.withAlphaComponent(UITheme.isLight ? 0.48 : 0.58).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.90).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawConnectors(in photoRect: CGRect) {
        guard showsConnectors else { return }
        let stroke = UITheme.waterInkMuted.withAlphaComponent(UITheme.isLight ? 0.52 : 0.70)
        stroke.setStroke()
        for item in XiaomiRemote2ProDiagramSpec.items {
            let anchor = XiaomiRemote2ProDiagramSpec.point(for: item, in: photoRect)
            let endpointY = photoRect.minY + item.calloutY * photoRect.height
            let exitX: CGFloat
            let endpointX: CGFloat
            switch item.side {
            case .left:
                exitX = photoRect.minX - 9 - CGFloat(item.order % 3) * 3
                endpointX = photoRect.minX - XiaomiRemote2ProDiagramSpec.connectorGap
            case .right:
                exitX = photoRect.maxX + 9 + CGFloat(item.order % 3) * 3
                endpointX = photoRect.maxX + XiaomiRemote2ProDiagramSpec.connectorGap
            }

            let path = NSBezierPath()
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: anchor)
            path.line(to: CGPoint(x: exitX, y: anchor.y))
            path.line(to: CGPoint(x: exitX, y: endpointY))
            path.line(to: CGPoint(x: endpointX, y: endpointY))
            path.stroke()

            let endpoint = NSBezierPath(ovalIn: CGRect(
                x: anchor.x - 2,
                y: anchor.y - 2,
                width: 4,
                height: 4
            ))
            stroke.setFill()
            endpoint.fill()
        }
    }
}
