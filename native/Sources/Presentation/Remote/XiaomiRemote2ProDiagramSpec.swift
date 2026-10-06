import CoreGraphics

enum RemoteCalloutSide: Equatable {
    case left
    case right
}

struct RemoteButtonDiagramItem: Equatable {
    let button: RemoteButton
    let side: RemoteCalloutSide
    let order: Int
    /// Normalized within the remote body, measured from the top-left.
    let anchor: CGPoint
    /// Normalized within the remote body height, measured from the top.
    let calloutY: CGFloat
}

enum XiaomiRemote2ProDiagramSpec {
    static let remoteWidth: CGFloat = 156
    static let remoteHeight: CGFloat = 440
    static let regularHeight: CGFloat = 480
    static let compactHeight: CGFloat = 800
    static let compactBreakpoint: CGFloat = 500
    static let connectorGap: CGFloat = 18

    static let items: [RemoteButtonDiagramItem] = [
        RemoteButtonDiagramItem(
            button: .power,
            side: .left,
            order: 0,
            anchor: CGPoint(x: 0.25, y: 0.098),
            calloutY: 0.06
        ),
        RemoteButtonDiagramItem(
            button: .dpadUp,
            side: .left,
            order: 1,
            anchor: CGPoint(x: 0.35, y: 0.166),
            calloutY: 0.18
        ),
        RemoteButtonDiagramItem(
            button: .dpadLeft,
            side: .left,
            order: 2,
            anchor: CGPoint(x: 0.24, y: 0.242),
            calloutY: 0.30
        ),
        RemoteButtonDiagramItem(
            button: .back,
            side: .left,
            order: 3,
            anchor: CGPoint(x: 0.29, y: 0.383),
            calloutY: 0.43
        ),
        RemoteButtonDiagramItem(
            button: .home,
            side: .left,
            order: 4,
            anchor: CGPoint(x: 0.29, y: 0.471),
            calloutY: 0.58
        ),
        RemoteButtonDiagramItem(
            button: .menu,
            side: .left,
            order: 5,
            anchor: CGPoint(x: 0.29, y: 0.555),
            calloutY: 0.72
        ),
        RemoteButtonDiagramItem(
            button: .voice,
            side: .right,
            order: 0,
            anchor: CGPoint(x: 0.75, y: 0.098),
            calloutY: 0.06
        ),
        RemoteButtonDiagramItem(
            button: .dpadRight,
            side: .right,
            order: 1,
            anchor: CGPoint(x: 0.76, y: 0.242),
            calloutY: 0.18
        ),
        RemoteButtonDiagramItem(
            button: .center,
            side: .right,
            order: 2,
            anchor: CGPoint(x: 0.59, y: 0.242),
            calloutY: 0.30
        ),
        RemoteButtonDiagramItem(
            button: .dpadDown,
            side: .right,
            order: 3,
            anchor: CGPoint(x: 0.65, y: 0.318),
            calloutY: 0.42
        ),
        RemoteButtonDiagramItem(
            button: .volumeUp,
            side: .right,
            order: 4,
            anchor: CGPoint(x: 0.70, y: 0.383),
            calloutY: 0.54
        ),
        RemoteButtonDiagramItem(
            button: .volumeDown,
            side: .right,
            order: 5,
            anchor: CGPoint(x: 0.70, y: 0.471),
            calloutY: 0.67
        ),
        RemoteButtonDiagramItem(
            button: .tv,
            side: .right,
            order: 6,
            anchor: CGPoint(x: 0.70, y: 0.555),
            calloutY: 0.82
        ),
    ]

    static func bodyRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.midX - remoteWidth / 2,
            y: 20,
            width: remoteWidth,
            height: remoteHeight
        )
    }

    static func point(for item: RemoteButtonDiagramItem, in bodyRect: CGRect) -> CGPoint {
        CGPoint(
            x: bodyRect.minX + item.anchor.x * bodyRect.width,
            y: bodyRect.minY + item.anchor.y * bodyRect.height
        )
    }
}
