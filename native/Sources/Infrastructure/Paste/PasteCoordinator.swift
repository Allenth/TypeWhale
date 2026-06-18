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

final class PasteCoordinator {
    private enum TextInsertionMode {
        case directUnicodeTyping
        case pasteboardShortcut
    }

    private struct Request {
        let text: String
        let targetApp: NSRunningApplication?
        let completion: (PasteOutcome) -> Void
    }

    private let insertionMode: TextInsertionMode = .pasteboardShortcut
    private var requests: [Request] = []
    private var isProcessing = false

    func enqueue(text: String, targetApp: NSRunningApplication?, completion: @escaping (PasteOutcome) -> Void) {
        requests.append(Request(text: text, targetApp: targetApp, completion: completion))
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
        guard targetApp.activate(options: []) else {
            finish(request, outcome: .failed("无法激活录音开始时的目标应用"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard frontmostPID == targetApp.processIdentifier else {
                if attempt < 1 {
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
        finish(request, outcome: .directInserted)
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
            finish(request, outcome: .failed("目标应用焦点已变化，已取消自动粘贴"))
            return
        }
        let pasteboard = NSPasteboard.general
        let previous = PasteboardSnapshot(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(request.text, forType: .string) else {
            previous.restore(to: pasteboard)
            finish(request, outcome: .failed("无法写入系统剪贴板"))
            return
        }
        let injectedChangeCount = pasteboard.changeCount

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if pasteboard.changeCount == injectedChangeCount {
                previous.restore(to: pasteboard)
                self.finish(request, outcome: .restored)
            } else {
                self.finish(request, outcome: .preservedUserClipboard)
            }
        }
    }

    private func finish(_ request: Request, outcome: PasteOutcome) {
        request.completion(outcome)
        isProcessing = false
        processNextIfNeeded()
    }
}
