import AppKit
import QuartzCore

final class RecordingPanel: NSPanel {
    private let visualBackground = NSVisualEffectView()
    private let capsule = RecordingCapsuleView()
    private let fadeDuration: TimeInterval = 0.25
    private let resizeDuration: TimeInterval = 0.18

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 164, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        visualBackground.frame = NSRect(x: 0, y: 0, width: 164, height: 44)
        visualBackground.autoresizingMask = [.width, .height]
        visualBackground.material = .hudWindow
        visualBackground.blendingMode = .behindWindow
        visualBackground.state = .active
        visualBackground.appearance = NSAppearance(named: .vibrantDark)
        visualBackground.wantsLayer = true
        visualBackground.layer?.cornerRadius = 21
        visualBackground.layer?.masksToBounds = true

        capsule.frame = visualBackground.bounds
        capsule.autoresizingMask = [.width, .height]
        visualBackground.addSubview(capsule)
        contentView = visualBackground
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(state: String, draft: String? = nil) {
        let shouldFadeIn = !isVisible
        capsule.update(state: state, draft: draft)
        resizeAndPosition()
        if shouldFadeIn {
            alphaValue = 0
        }
        orderFrontRegardless()
        if shouldFadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    func updateDraft(_ draft: String) {
        capsule.update(draft: draft)
        resizeAndPosition()
    }

    func hideAnimated() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        }
    }

    private func resizeAndPosition() {
        let size = capsule.preferredSize
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let anchorCenter = NSPoint(x: frame.midX, y: frame.minY + 68)
        let targetFrame = NSRect(
            x: anchorCenter.x - size.width / 2,
            y: anchorCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        guard isVisible else {
            setFrame(targetFrame, display: true)
            return
        }
        if abs(self.frame.width - targetFrame.width) < 0.5,
           abs(self.frame.height - targetFrame.height) < 0.5,
           abs(self.frame.origin.x - targetFrame.origin.x) < 0.5,
           abs(self.frame.origin.y - targetFrame.origin.y) < 0.5 {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(targetFrame, display: true)
        }
    }

    func updateBands(_ bands: [Float]) {
        capsule.update(bands: bands)
    }
}
