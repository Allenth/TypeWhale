import AppKit
import QuartzCore

final class MinimalBlackPreviewPresenter: PreviewPresenting {
    static let panelSize = NSSize(width: 252, height: 40)

    var onCycleMode: (() -> Void)?
    var presentationFrame: CGRect? { panel.frame }

    private let panel: MinimalBlackPreviewPanel
    private let previewView = MinimalBlackPreviewView()
    private let panelShell = MainCapsulePanelShell()
    private var renderState = MinimalBlackRenderState.empty
    private var motion = MinimalBlackTextMotion()
    private var animationTimer: Timer?
    private var visibilityGeneration = 0
    private let animationStepInterval: TimeInterval = 0.05
    private let fadeDuration: TimeInterval = 0.18

    init() {
        panel = MinimalBlackPreviewPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = previewView
    }

    deinit {
        animationTimer?.invalidate()
    }

    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {
        _ = (appIcon, appName, modeName, autoTranslateEnabled)
    }

    func updateTargetApp(appIcon: NSImage?, appName: String?) {
        _ = (appIcon, appName)
    }

    func updateModeName(_ modeName: String) {
        _ = modeName
    }

    func updateAutoTranslateEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {
        _ = remainingSeconds
        previewView.updateMemoryHigh(memoryHigh)
    }

    func show(state: String, draft: String?) {
        visibilityGeneration += 1
        previewView.updateStatus(state)
        if let draft {
            applyContent(stableWindowText: "", volatileTailText: draft)
        }
        position()
        let shouldFadeIn = !panel.isVisible
        if shouldFadeIn { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        if shouldFadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
        LaunchDiagnostics.mark(
            "capsule_show_result theme=minimalBlack visible=\(panel.isVisible) alpha=\(String(format: "%.2f", panel.alphaValue)) fade_in=\(shouldFadeIn) frame=\(Int(panel.frame.minX)),\(Int(panel.frame.minY)),\(Int(panel.frame.width))x\(Int(panel.frame.height))"
        )
    }

    func updateDraft(_ draft: String) {
        applyContent(stableWindowText: "", volatileTailText: draft)
    }

    func updateDraft(_ snapshot: PreviewDisplaySnapshot) {
        applyContent(
            stableWindowText: snapshot.stableWindowText,
            volatileTailText: snapshot.volatileTailText
        )
    }

    func hideAnimated() {
        guard panel.isVisible else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        stopAnimationTimer()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.visibilityGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.motion.reset()
                self.renderState = .empty
                self.previewView.reset()
            }
        }
    }

    func updateBands(_ bands: [Float]) {
        previewView.updateBands(bands)
    }

    func updateInputLevel(db: Float?) {
        previewView.updateInputLevel(db)
    }

    private func applyContent(stableWindowText: String, volatileTailText: String) {
        renderState.apply(
            stableWindowText: stableWindowText,
            volatileTailText: volatileTailText
        )
        _ = motion.apply(contentCharacterCount: renderState.displayText.count)
        renderState.visibleCharacterCount = motion.visibleCharacterCount
        previewView.apply(renderState)
        if motion.needsTimer {
            startAnimationTimerIfNeeded()
        } else {
            stopAnimationTimer()
        }
    }

    private func startAnimationTimerIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: animationStepInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                switch self.motion.advance() {
                case .advanced:
                    self.renderState.visibleCharacterCount = self.motion.visibleCharacterCount
                    self.previewView.apply(self.renderState)
                case .finished:
                    self.renderState.visibleCharacterCount = self.motion.visibleCharacterCount
                    self.previewView.apply(self.renderState)
                    self.stopAnimationTimer()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(
            panelShell.targetFrame(
                panelSize: Self.panelSize,
                screenVisibleFrame: screen.visibleFrame
            ),
            display: true
        )
    }

    /// 主题选择页使用的静态快照，复用生产视图及渲染状态。
    func makeThemePreviewSnapshot(text: String) -> NSImage? {
        renderState = .empty
        renderState.apply(stableWindowText: text, volatileTailText: "")
        renderState.visibleCharacterCount = renderState.displayText.count
        previewView.frame = NSRect(origin: .zero, size: Self.panelSize)
        previewView.apply(renderState)
        previewView.layoutSubtreeIfNeeded()
        previewView.displayIfNeeded()
        return previewView.typeWhaleSnapshotImage()
    }
}

private final class MinimalBlackPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
