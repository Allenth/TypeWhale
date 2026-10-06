import AppKit
import AVFoundation
import QuartzCore

@MainActor
final class LaunchAnimationPresenter {
    static let shared = LaunchAnimationPresenter()

    private let resourceName = "TypeWhaleInkWhaleAlpha"
    private let resourceExtension = "mov"
    private let maximumPlaybackSeconds: TimeInterval = 6.0
    private var window: NSWindow?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?

    private init() {}

    func playIfNeeded() {
        guard LaunchAnimationPlaybackStore.shouldPlayFirstLaunch else {
            LaunchDiagnostics.mark("launch_animation skipped reason=already_played")
            return
        }
        LaunchAnimationPlaybackStore.markPlayed()
        play(reason: "first_launch")
    }

    func replayFromSettings() {
        play(reason: "settings_replay")
    }

    private func play(reason: String) {
        guard window == nil else {
            LaunchDiagnostics.mark("launch_animation skipped reason=already_visible")
            return
        }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Launch"
        ) else {
            LaunchDiagnostics.mark("launch_animation missing_resource name=\(resourceName).\(resourceExtension)")
            return
        }
        guard let screen = NSScreen.main else {
            LaunchDiagnostics.mark("launch_animation skipped reason=no_main_screen")
            return
        }

        let contentView = LaunchAnimationView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView.onDismiss = { [weak self] in
            self?.finishPlayback(reason: "manual_dismiss")
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.actionAtItemEnd = .pause

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = contentView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.addSublayer(playerLayer)

        let overlayWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.contentView = contentView
        overlayWindow.makeKeyAndOrderFront(nil)

        self.window = overlayWindow
        self.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishPlayback(reason: "ended")
            }
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.finishPlayback(reason: "timeout")
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumPlaybackSeconds, execute: timeout)

        LaunchDiagnostics.mark("launch_animation play reason=\(reason)")
        player.play()
    }

    private func finishPlayback(reason: String) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player?.pause()
        player = nil
        window?.orderOut(nil)
        window = nil
        LaunchDiagnostics.mark("launch_animation finish reason=\(reason)")
    }
}

private final class LaunchAnimationView: NSView {
    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}
