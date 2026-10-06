import AppKit

enum MainCapsuleShellAccent: Equatable {
    case normal
    case ideaPill
    case openClaw
}

struct MainCapsuleShell {
    static let compactSize = NSSize(width: 176, height: 42)
    static let maxPreviewWidth: CGFloat = 300
    static let horizontalPadding: CGFloat = 18
    static let openClawBadgeRightOverhang: CGFloat = 18
    static let openClawBadgeTopOverhang: CGFloat = 9

    let cornerRadius: CGFloat = 20

    func preferredSize(
        hasText: Bool,
        retainedPreviewWidth: CGFloat,
        measuredPreviewWidth: CGFloat,
        contextTopInset: CGFloat,
        accent: MainCapsuleShellAccent
    ) -> NSSize {
        let height = Self.compactSize.height + contextTopInset
        let width = hasText ? max(retainedPreviewWidth, measuredPreviewWidth) : Self.compactSize.width
        guard accent == .openClaw else {
            return NSSize(width: width, height: height)
        }
        return NSSize(
            width: width + Self.openClawBadgeRightOverhang,
            height: height + Self.openClawBadgeTopOverhang
        )
    }

    func previewWidth(forMeasuredTextWidth measuredTextWidth: CGFloat) -> CGFloat {
        min(
            Self.maxPreviewWidth,
            max(Self.compactSize.width, ceil(measuredTextWidth) + Self.horizontalPadding * 2)
        )
    }

    func materialFrame(for size: NSSize, accent: MainCapsuleShellAccent) -> NSRect {
        guard accent == .openClaw else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: 0,
            y: 0,
            width: size.width - Self.openClawBadgeRightOverhang,
            height: size.height - Self.openClawBadgeTopOverhang
        )
    }

    func bodyRect(in bounds: NSRect, accent: MainCapsuleShellAccent) -> NSRect {
        if accent == .openClaw {
            return NSRect(
                x: 1,
                y: 1,
                width: bounds.width - Self.openClawBadgeRightOverhang - 2,
                height: bounds.height - Self.openClawBadgeTopOverhang - 2
            )
        }
        return bounds.insetBy(dx: 1, dy: 1)
    }
}
