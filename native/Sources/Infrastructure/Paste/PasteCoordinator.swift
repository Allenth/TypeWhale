import AppKit
import ApplicationServices
import Foundation

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(from pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.compactMap { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values.isEmpty ? nil : values
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}

struct PasteboardReadinessGate {
    enum Decision: Equatable {
        case ready
        case retry
        case stolen
    }

    struct Snapshot {
        let expectedText: String
        let injectedChangeCount: Int
        let currentChangeCount: Int
        let currentString: String?
    }

    static func evaluate(_ snapshot: Snapshot) -> Decision {
        if snapshot.currentString == snapshot.expectedText {
            return .ready
        }
        if snapshot.currentChangeCount != snapshot.injectedChangeCount {
            return .stolen
        }
        return .retry
    }
}

@MainActor
final class PasteCoordinator {
    private enum PasteboardTiming {
        static let readinessRetryDelay: TimeInterval = 0.015
        static let maximumReadinessAttempts = 8
        static let restorationDelay: TimeInterval = 0.3
    }

    private enum TextInsertionMode {
        case directUnicodeTyping
        case pasteboardShortcut
    }

    private struct Request {
        let taskID: UUID
        let text: String
        let targetApp: NSRunningApplication?
        let postPasteAction: PostPasteAction
        let completion: (PasteOutcome) -> Void
    }

    private let insertionMode: TextInsertionMode = .pasteboardShortcut
    private let postPasteActionScheduler: any PostPasteActionScheduling
    private var requests: [Request] = []
    private var isProcessing = false

    init(
        postPasteActionScheduler: any PostPasteActionScheduling
    ) {
        self.postPasteActionScheduler = postPasteActionScheduler
    }

    func enqueue(
        taskID: UUID,
        text: String,
        targetApp: NSRunningApplication?,
        postPasteAction: PostPasteAction = .none,
        completion: @escaping (PasteOutcome) -> Void
    ) {
        requests.append(Request(
            taskID: taskID,
            text: text,
            targetApp: targetApp,
            postPasteAction: postPasteAction,
            completion: completion
        ))
        processNextIfNeeded()
    }

    private func processNextIfNeeded() {
        guard !isProcessing, !requests.isEmpty else { return }
        isProcessing = true
        let request = requests.removeFirst()
        activateTarget(for: request, attempt: 0)
    }

    private func activateTarget(for request: Request, attempt: Int) {
        guard let targetApp = request.targetApp, !targetApp.isTerminated else {
            finish(request, outcome: .failed("录音开始时的目标应用已关闭"))
            return
        }
        let frontmostBeforeActivation = NSWorkspace.shared.frontmostApplication
        let didDismissTransientUI = Self.dismissTransientSystemUIIfNeeded(
            frontmostBeforeActivation,
            targetApp: targetApp,
            attempt: attempt
        )
        let activationDelay: TimeInterval = didDismissTransientUI ? 0.14 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { [weak self] in
            self?.activatePreparedTarget(for: request, attempt: attempt)
        }
    }

    private func activatePreparedTarget(for request: Request, attempt: Int) {
        guard let targetApp = request.targetApp, !targetApp.isTerminated else {
            finish(request, outcome: .failed("录音开始时的目标应用已关闭"))
            return
        }
        LaunchDiagnostics.mark(
            "paste_activate_start target=\(Self.logApp(targetApp)) frontmost=\(Self.logApp(NSWorkspace.shared.frontmostApplication)) attempt=\(attempt)"
        )
        guard targetApp.activate(options: []) else {
            LaunchDiagnostics.mark(
                "paste_activate_failed target=\(Self.logApp(targetApp)) frontmost=\(Self.logApp(NSWorkspace.shared.frontmostApplication)) attempt=\(attempt) reason=activate_returned_false"
            )
            finish(request, outcome: .failed("无法激活录音开始时的目标应用"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard frontmostPID == targetApp.processIdentifier else {
                LaunchDiagnostics.mark(
                    "paste_activate_wait target=\(Self.logApp(targetApp)) frontmost=\(Self.logApp(NSWorkspace.shared.frontmostApplication)) attempt=\(attempt)"
                )
                if attempt < 2 {
                    self.activateTarget(for: request, attempt: attempt + 1)
                } else {
                    self.finish(request, outcome: .failed("目标应用未能获得输入焦点，已取消自动粘贴"))
                }
                return
            }
            switch self.insertionMode {
            case .directUnicodeTyping:
                self.performDirectUnicodeTyping(request)
            case .pasteboardShortcut:
                self.performPasteboardShortcut(request)
            }
        }
    }

    private func performDirectUnicodeTyping(_ request: Request) {
        guard let targetApp = request.targetApp,
              !targetApp.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
            finish(request, outcome: .failed("目标应用焦点已变化，已取消直接输入"))
            return
        }
        guard postUnicodeText(request.text) else {
            finish(request, outcome: .failed("无法创建系统直接输入事件"))
            return
        }
        finish(request, outcome: .directInserted(Date()))
    }

    private func postUnicodeText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.localEventsSuppressionInterval = 0

        for character in text {
            let units = Array(String(character).utf16)
            guard !units.isEmpty,
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    private func performPasteboardShortcut(_ request: Request) {
        guard let targetApp = request.targetApp,
              !targetApp.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
            LaunchDiagnostics.mark(
                "paste_cancelled reason=focus_changed target=\(Self.logApp(request.targetApp)) frontmost=\(Self.logApp(NSWorkspace.shared.frontmostApplication))"
            )
            finish(request, outcome: .failed("目标应用焦点已变化，已取消自动粘贴"))
            return
        }
        let pasteboard = NSPasteboard.general
        let restoredClipboardText = pasteboard.string(forType: .string)
        let previous = PasteboardSnapshot(from: pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(request.text, forType: .string),
              let marker = Self.readerSourceMarker(
                  restoredClipboardText: restoredClipboardText
              ),
              item.setData(
                  marker,
                  forType: NSPasteboard.PasteboardType(
                      ReaderClipboardMarker.pasteboardTypeRawValue
                  )
              ),
              pasteboard.writeObjects([item]) else {
            previous.restore(to: pasteboard)
            finish(request, outcome: .failed("无法写入系统剪贴板"))
            return
        }
        let injectedChangeCount = pasteboard.changeCount

        waitForPasteboardReadiness(
            request,
            pasteboard: pasteboard,
            previous: previous,
            injectedChangeCount: injectedChangeCount,
            attempt: 0
        )
    }

    private func waitForPasteboardReadiness(
        _ request: Request,
        pasteboard: NSPasteboard,
        previous: PasteboardSnapshot,
        injectedChangeCount: Int,
        attempt: Int
    ) {
        let decision = PasteboardReadinessGate.evaluate(PasteboardReadinessGate.Snapshot(
            expectedText: request.text,
            injectedChangeCount: injectedChangeCount,
            currentChangeCount: pasteboard.changeCount,
            currentString: pasteboard.string(forType: .string)
        ))

        switch decision {
        case .ready:
            postPasteboardShortcut(
                request,
                pasteboard: pasteboard,
                previous: previous,
                injectedChangeCount: injectedChangeCount
            )
        case .retry:
            guard attempt < PasteboardTiming.maximumReadinessAttempts else {
                previous.restore(to: pasteboard)
                LaunchDiagnostics.mark(
                    "paste_cancelled reason=pasteboard_not_ready target=\(Self.logApp(request.targetApp)) attempts=\(attempt + 1)"
                )
                finish(request, outcome: .failed("系统剪贴板尚未准备好，已取消自动粘贴"))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + PasteboardTiming.readinessRetryDelay) { [weak self] in
                self?.waitForPasteboardReadiness(
                    request,
                    pasteboard: pasteboard,
                    previous: previous,
                    injectedChangeCount: injectedChangeCount,
                    attempt: attempt + 1
                )
            }
        case .stolen:
            LaunchDiagnostics.mark(
                "paste_cancelled reason=pasteboard_changed_before_paste target=\(Self.logApp(request.targetApp)) attempt=\(attempt)"
            )
            finish(request, outcome: .failed("系统剪贴板已被其他内容更新，已取消自动粘贴"))
        }
    }

    private func postPasteboardShortcut(
        _ request: Request,
        pasteboard: NSPasteboard,
        previous: PasteboardSnapshot,
        injectedChangeCount: Int
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        guard let down, let up else {
            previous.restore(to: pasteboard)
            finish(request, outcome: .failed("无法创建系统粘贴事件"))
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        let pasteCompletedAt = Date()

        schedulePostPasteActionIfNeeded(for: request)
        DispatchQueue.main.asyncAfter(deadline: .now() + PasteboardTiming.restorationDelay) { [weak self] in
            guard let self else { return }
            if pasteboard.changeCount == injectedChangeCount {
                previous.restore(to: pasteboard)
                self.finish(request, outcome: .restored(pasteCompletedAt))
            } else {
                self.finish(request, outcome: .preservedUserClipboard(pasteCompletedAt))
            }
        }
    }

    private func schedulePostPasteActionIfNeeded(for request: Request) {
        guard let targetApp = request.targetApp,
              PostPasteActionSchedulingGate.shouldSchedule(
                  request.postPasteAction
              ) else {
            return
        }
        postPasteActionScheduler.schedule(
            action: request.postPasteAction,
            taskID: request.taskID,
            targetPID: targetApp.processIdentifier,
            targetBundleIdentifier: targetApp.bundleIdentifier
        )
    }

    private func finish(_ request: Request, outcome: PasteOutcome) {
        LaunchDiagnostics.mark(
            "paste_finish target=\(Self.logApp(request.targetApp)) outcome=\(outcome.logName)"
        )
        request.completion(outcome)
        isProcessing = false
        processNextIfNeeded()
    }

    private static func logApp(_ app: NSRunningApplication?) -> String {
        guard let app else { return "nil" }
        let name = app.localizedName ?? "unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"
        return "\(name)[\(bundleID)#\(app.processIdentifier)]"
    }

    private static func dismissTransientSystemUIIfNeeded(
        _ frontmostApp: NSRunningApplication?,
        targetApp: NSRunningApplication,
        attempt: Int
    ) -> Bool {
        guard isTransientSystemUIApp(frontmostApp) else { return false }
        let posted = postEscapeKey()
        LaunchDiagnostics.mark(
            "paste_dismiss_transient_ui frontmost=\(logApp(frontmostApp)) target=\(logApp(targetApp)) attempt=\(attempt) escape_posted=\(posted)"
        )
        return posted
    }

    private static func isTransientSystemUIApp(_ app: NSRunningApplication?) -> Bool {
        guard let app, !app.isTerminated else { return false }
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? ""
        let blockedBundleIDs: Set<String> = [
            "com.apple.ControlCenter",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.bjango.istatmenus.status",
            "com.bjango.istatmenus.agent",
        ]
        if blockedBundleIDs.contains(bundleID) {
            return true
        }
        let loweredName = name.lowercased()
        return loweredName == "control center" ||
            loweredName == "控制中心" ||
            loweredName == "notification center" ||
            loweredName == "通知中心" ||
            loweredName == "systemuiserver" ||
            loweredName.contains("menubar")
    }

    private static func postEscapeKey() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return false
        }
        source.localEventsSuppressionInterval = 0
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func readerSourceMarker(
        restoredClipboardText: String?
    ) -> Data? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return nil
        }
        return try? ReaderClipboardMarker.encode(
            producerBundleIdentifier: bundleIdentifier,
            restoredClipboardText: restoredClipboardText
        )
    }
}
