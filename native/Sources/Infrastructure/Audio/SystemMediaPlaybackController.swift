import AppKit
import ApplicationServices
import Foundation

enum SyntheticMediaKeyEvent {
    static let eventSourceUserData: Int64 = 0x5457_4D45

    private static let auxControlButtonSubtype: Int16 = 8
    private static let playKeyCode = 16
    private static let keyDownState = 0x0A
    private static let keyUpState = 0x0B

    static func isTypeWhaleGenerated(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == eventSourceUserData
    }

    static func makePlayPauseEvents(markAsTypeWhaleGenerated: Bool = true) -> [CGEvent]? {
        guard let keyDown = makePlayPauseEvent(
            keyState: keyDownState,
            markAsTypeWhaleGenerated: markAsTypeWhaleGenerated
        ),
        let keyUp = makePlayPauseEvent(
            keyState: keyUpState,
            markAsTypeWhaleGenerated: markAsTypeWhaleGenerated
        ) else {
            return nil
        }
        return [keyDown, keyUp]
    }

    static func postPlayPause() -> Bool {
        guard let events = makePlayPauseEvents() else { return false }
        events.forEach { $0.post(tap: .cghidEventTap) }
        return true
    }

    private static func makePlayPauseEvent(keyState: Int, markAsTypeWhaleGenerated: Bool) -> CGEvent? {
        let data1 = (playKeyCode << 16) | (keyState << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: auxControlButtonSubtype,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return nil
        }
        if markAsTypeWhaleGenerated {
            event.setIntegerValueField(.eventSourceUserData, value: eventSourceUserData)
        }
        return event
    }
}

final class SystemMediaPlaybackController {
    private static let defaultResumeDelay: TimeInterval = 1.0

    private let stateProvider: SystemMediaPlaybackStateProviding
    private let resumeDelay: TimeInterval
    private let emitPlayPause: () -> Bool
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private let log: (String) -> Void
    private var recordingActive = false
    private var ownedProcessID: pid_t?
    private var resumeWorkItem: DispatchWorkItem?
    private var generation: UInt = 0

    init(
        stateProvider: SystemMediaPlaybackStateProviding = MediaRemoteSystemPlaybackStateProvider(),
        resumeDelay: TimeInterval = SystemMediaPlaybackController.defaultResumeDelay,
        emitPlayPause: @escaping () -> Bool = SyntheticMediaKeyEvent.postPlayPause,
        schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, workItem in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        },
        log: @escaping (String) -> Void = LaunchDiagnostics.mark
    ) {
        self.stateProvider = stateProvider
        self.resumeDelay = resumeDelay
        self.emitPlayPause = emitPlayPause
        self.schedule = schedule
        self.log = log
    }

    func pauseIfNeeded(enabled: Bool) {
        guard enabled else { return }
        recordingActive = true
        cancelPendingResumeAndAdvanceGeneration()
        guard ownedProcessID == nil else {
            log("system_media_pause coalesced=true")
            return
        }

        let requestGeneration = generation
        stateProvider.fetchSnapshot { [weak self] snapshot in
            guard let self,
                  self.generation == requestGeneration,
                  self.recordingActive,
                  self.ownedProcessID == nil else {
                return
            }
            guard snapshot.state == .playing,
                  let processID = snapshot.processID,
                  processID > 0 else {
                self.log("system_media_pause skipped=\(Self.logValue(for: snapshot.state))")
                return
            }
            guard self.emitPlayPause() else {
                self.log("system_media_pause emitted=false")
                return
            }
            self.ownedProcessID = processID
            self.log("system_media_pause emitted=true")
        }
    }

    func resume() {
        recordingActive = false
        guard resumeWorkItem == nil else { return }
        generation &+= 1
        guard let ownedProcessID else { return }

        let scheduledGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == scheduledGeneration,
                  !self.recordingActive,
                  self.ownedProcessID == ownedProcessID else {
                return
            }
            self.resumeWorkItem = nil
            self.stateProvider.fetchSnapshot { [weak self] snapshot in
                guard let self,
                      self.generation == scheduledGeneration,
                      !self.recordingActive,
                      self.ownedProcessID == ownedProcessID else {
                    return
                }

                self.ownedProcessID = nil
                guard snapshot.state == .paused,
                      snapshot.processID == ownedProcessID else {
                    self.log("system_media_resume skipped=\(Self.logValue(for: snapshot.state))")
                    return
                }
                guard self.emitPlayPause() else {
                    self.log("system_media_resume emitted=false")
                    return
                }
                self.log("system_media_resume emitted=true")
            }
        }
        resumeWorkItem = workItem
        schedule(resumeDelay, workItem)
    }

    private func cancelPendingResumeAndAdvanceGeneration() {
        generation &+= 1
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
    }

    private static func logValue(for state: SystemMediaPlaybackState) -> String {
        switch state {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .unknown:
            return "unknown"
        }
    }
}
