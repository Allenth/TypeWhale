import AppKit
import ApplicationServices
import CoreGraphics
import UniformTypeIdentifiers
import Vision

@MainActor
final class ScreenshotCoordinator {
    private var overlays: [ScreenshotOverlayWindow] = []
    private var escapeKeyLocalMonitor: Any?
    private var escapeKeyGlobalMonitor: Any?
    private var operationGeneration = 0
    private let ocrRecognizer = ScreenshotOCRRecognizer()
    private let translationEngine = SelectedSmartAITextEngine()
    private let onStatus: (String, String, MainViewController.PrimaryStatusTone) -> Void
    private static let escapeKeyCode: UInt16 = 53

    init(onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void) {
        self.onStatus = onStatus
    }

    var isActive: Bool {
        !overlays.isEmpty
    }

    func begin() {
        begin(preselectedWindowFrame: nil, autoTranslateAfterSelection: false)
    }

    func beginTranslation() {
        begin(preselectedWindowFrame: nil, autoTranslateAfterSelection: true)
    }

    private func begin(preselectedWindowFrame: CGRect?, autoTranslateAfterSelection: Bool) {
        guard !isActive else { return }
        invalidatePendingOperations()
        let windowCandidates = Self.visibleWindowCandidates()
        let screenOverlays = NSScreen.screens.compactMap { screen -> ScreenshotOverlayWindow? in
            guard let displayID = displayID(for: screen),
                  let image = captureFullScreen(displayID) else { return nil }
            return ScreenshotOverlayWindow(
                screen: screen,
                displayID: displayID,
                screenshot: image,
                windowCandidates: windowCandidates,
                preselectedWindowFrame: preselectedWindowFrame,
                autoTranslateAfterSelection: autoTranslateAfterSelection,
                onSelectWindow: { [weak self] candidate in
                    self?.focusWindowThenBeginScreenshot(candidate, autoTranslateAfterSelection: autoTranslateAfterSelection)
                },
                onCopy: { [weak self] image in self?.copy(image) },
                onOCR: { [weak self] image in self?.recognizeText(in: image) },
                onTranslate: { [weak self] image, completion in self?.translateText(in: image, completion: completion) },
                onSaved: { [weak self] url in self?.saved(url) },
                onCancel: { [weak self] in self?.cancel() },
                onStatus: { [weak self] status, detail, tone in self?.onStatus(status, detail, tone) }
            )
        }
        guard !screenOverlays.isEmpty else {
            onStatus("无法进入截图", "未能读取屏幕内容，请检查屏幕录制权限", .error)
            return
        }
        overlays = screenOverlays
        installEscapeKeyMonitors()
        overlays.forEach { $0.orderFrontRegardless() }
        // 只让截图覆盖层接收键盘事件，不激活 TypeWhale App，避免把已在后方的主页窗口推到最前。
        overlays.first?.makeKeyAndOrderFront(nil)
        if autoTranslateAfterSelection {
            onStatus("翻译截图", "拖拽选择区域，松开后自动 OCR 并翻译覆盖", .processing)
        } else if preselectedWindowFrame == nil {
            onStatus("截图模式", "拖拽选择区域，复制后会写入剪贴板", .processing)
        } else {
            onStatus("窗口已置顶", "边框已自动对齐窗口，可复制、OCR、标注或保存", .processing)
        }
    }

    private func focusWindowThenBeginScreenshot(_ candidate: ScreenshotWindowCandidate, autoTranslateAfterSelection: Bool) {
        operationGeneration += 1
        let generation = operationGeneration
        overlays.forEach { $0.setWindowRecapturePending(true) }
        onStatus("正在置顶窗口", "将选中的窗口移到最前后重新截图", .processing)
        raiseWindow(candidate)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self else { return }
            guard generation == self.operationGeneration else {
                // 置顶操作被打断/作废：若已无截图浮层在显示，复位主状态，
                // 避免“正在置顶窗口”+进度条永久残留在主会话区。若有新浮层接管则保留其状态。
                if self.overlays.isEmpty {
                    self.onStatus("等待录音", "Fn 录音", .idle)
                }
                return
            }
            let refreshedCandidates = Self.visibleWindowCandidates()
            let refreshedCandidate = refreshedCandidates.first { $0.windowID == candidate.windowID } ?? candidate
            var didRefreshAnyOverlay = false
            for overlay in self.overlays {
                guard let image = self.captureFullScreen(overlay.displayID, below: overlay) else { continue }
                didRefreshAnyOverlay = true
                overlay.replaceScreenshot(
                    image,
                    windowCandidates: refreshedCandidates,
                    preselectedWindowFrame: refreshedCandidate.frame
                )
            }
            guard didRefreshAnyOverlay else {
                self.overlays.forEach { $0.setWindowRecapturePending(false) }
                self.onStatus("无法更新截图", "未能读取置顶后的屏幕内容，请检查屏幕录制权限", .error)
                return
            }
            self.onStatus("窗口已置顶", "边框已自动对齐窗口，可复制、OCR、标注或保存", .processing)
        }
    }

    private func copy(_ image: NSImage) {
        invalidatePendingOperations()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        closeAll()
        onStatus("截图已复制", "已将选区截图写入剪贴板", .success)
    }

    private func cancel() {
        invalidatePendingOperations()
        closeAll()
        onStatus("截图已取消", "未改动剪贴板", .idle)
    }

    private func saved(_ url: URL) {
        invalidatePendingOperations()
        closeAll()
        let directoryName = url.deletingLastPathComponent().lastPathComponent
        showTransientStatus(
            "截图已保存",
            "已保存到\(directoryName)：\(url.lastPathComponent)",
            .success
        )
    }

    private func recognizeText(in image: NSImage) {
        operationGeneration += 1
        let generation = operationGeneration
        closeAll()
        onStatus("OCR 识别中", "正在识别选区文字", .processing)
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await ocrRecognizer.recognize(image: image).text
                guard generation == operationGeneration else { return }
                if text.isEmpty {
                    onStatus("未识别到文字", "可以调整截图范围后再试一次", .warning)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                closeAll()
                showTransientStatus("内容已复制", "OCR 识别结果已复制到剪贴板", .success)
            } catch {
                guard generation == operationGeneration else { return }
                onStatus("OCR 识别失败", error.localizedDescription, .error)
            }
        }
    }

    private func translateText(
        in image: NSImage,
        completion: @escaping (Result<ScreenshotTranslationResult, Error>) -> Void
    ) {
        operationGeneration += 1
        let generation = operationGeneration
        onStatus("截图翻译中", "正在识别选区英文内容", .processing)
        Task { [weak self] in
            guard let self else { return }
            do {
                let ocrResult = try await ocrRecognizer.recognize(image: image)
                let text = ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard generation == operationGeneration else { return }
                guard !text.isEmpty else {
                    completion(.failure(ScreenshotTranslationError.emptyOCR))
                    return
                }

                onStatus("截图翻译中", "正在翻译为中文", .processing)
                let source = Self.numberedScreenshotSource(from: ocrResult.lines)
                let output = try await translationEngine.translate(
                    rawText: source,
                    direction: .englishToChinese,
                    context: SmartInputContext(
                        targetAppName: "截图翻译",
                        targetBundleIdentifier: "TypeWhale.ScreenshotTranslation"
                    ),
                    triggeredBy: "screenshot_translation"
                )
                guard generation == operationGeneration else { return }
                SmartUsageLedgerStore.record(output.usage)
                let translatedLines = Self.parseScreenshotLineTranslations(
                    output.translatedText,
                    lines: ocrResult.lines
                )
                completion(.success(ScreenshotTranslationResult(
                    translatedText: output.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                    translatedLines: translatedLines
                )))
            } catch {
                guard generation == operationGeneration else { return }
                completion(.failure(error))
            }
        }
    }

    private static func numberedScreenshotSource(from lines: [ScreenshotOCRLine]) -> String {
        lines.enumerated()
            .map { index, line in "[[TW_LINE_\(index + 1)]] \(line.text)" }
            .joined(separator: "\n")
    }

    private static func parseScreenshotLineTranslations(
        _ translatedText: String,
        lines: [ScreenshotOCRLine]
    ) -> [ScreenshotTranslatedLine] {
        let pattern = #"^\s*\[\[TW_LINE_(\d+)\]\]\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        var buckets: [Int: [String]] = [:]
        var currentID: Int?

        translatedText.components(separatedBy: .newlines).forEach { outputLine in
            let range = NSRange(outputLine.startIndex..<outputLine.endIndex, in: outputLine)
            if let match = regex?.firstMatch(in: outputLine, range: range),
               match.numberOfRanges >= 3,
               let idRange = Range(match.range(at: 1), in: outputLine),
               let id = Int(outputLine[idRange]) {
                currentID = id
                if let textRange = Range(match.range(at: 2), in: outputLine) {
                    let text = outputLine[textRange].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        buckets[id, default: []].append(text)
                    }
                }
            } else if let currentID {
                let text = outputLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    buckets[currentID, default: []].append(text)
                }
            }
        }

        return lines.enumerated().compactMap { index, line in
            let text = (buckets[index + 1] ?? [])
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ScreenshotTranslatedLine(text: text, rect: line.rect)
        }
    }

    private func closeAll() {
        removeEscapeKeyMonitors()
        overlays.forEach {
            ($0.contentView as? ScreenshotOverlayView)?.discardActiveTextField()
            $0.orderOut(nil)
        }
        overlays.removeAll()
    }

    private func installEscapeKeyMonitors() {
        removeEscapeKeyMonitors()
        escapeKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode, self?.isActive == true else {
                return event
            }
            self?.cancel()
            return nil
        }
        escapeKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            DispatchQueue.main.async { [weak self] in
                guard self?.isActive == true else { return }
                self?.cancel()
            }
        }
    }

    private func removeEscapeKeyMonitors() {
        if let escapeKeyLocalMonitor {
            NSEvent.removeMonitor(escapeKeyLocalMonitor)
        }
        if let escapeKeyGlobalMonitor {
            NSEvent.removeMonitor(escapeKeyGlobalMonitor)
        }
        escapeKeyLocalMonitor = nil
        escapeKeyGlobalMonitor = nil
    }

    private func invalidatePendingOperations() {
        operationGeneration += 1
    }

    private func showTransientStatus(_ status: String, _ detail: String, _ tone: MainViewController.PrimaryStatusTone) {
        let generation = operationGeneration
        onStatus(status, detail, tone)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let self, generation == operationGeneration else { return }
            onStatus("等待录音", "Fn 录音", .idle)
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func captureFullScreen(_ displayID: CGDirectDisplayID) -> CGImage? {
        CGDisplayCreateImage(displayID)
    }

    private func captureFullScreen(_ displayID: CGDirectDisplayID, below overlay: ScreenshotOverlayWindow) -> CGImage? {
        let overlayWindowID = CGWindowID(overlay.windowNumber)
        guard overlayWindowID != 0 else {
            return captureFullScreen(displayID)
        }
        return CGWindowListCreateImage(
            CGDisplayBounds(displayID),
            [.optionOnScreenBelowWindow],
            overlayWindowID,
            [.bestResolution]
        ) ?? captureFullScreen(displayID)
    }

    private static func visibleWindowCandidates() -> [ScreenshotWindowCandidate] {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info -> ScreenshotWindowCandidate? in
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            guard layer == 0,
                  alpha > 0.01,
                  let ownerPID,
                  let windowID,
                  let rawBounds = info[kCGWindowBounds as String],
                  let boundsDictionary = rawBounds as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDictionary),
                  frame.width >= 48,
                  frame.height >= 48 else {
                return nil
            }
            return ScreenshotWindowCandidate(windowID: CGWindowID(windowID), ownerPID: ownerPID, frame: frame)
        }
    }

    private func raiseWindow(_ candidate: ScreenshotWindowCandidate) {
        let app = AXUIElementCreateApplication(candidate.ownerPID)
        if let axWindow = matchingAXWindow(in: app, for: candidate) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, axWindow)
        }
        NSRunningApplication(processIdentifier: candidate.ownerPID)?.activate(options: [])
    }

    private func matchingAXWindow(in app: AXUIElement, for candidate: ScreenshotWindowCandidate) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }
        return windows.first { axWindow in
            guard let frame = frame(of: axWindow) else { return false }
            return abs(frame.minX - candidate.frame.minX) <= 3
                && abs(frame.minY - candidate.frame.minY) <= 3
                && abs(frame.width - candidate.frame.width) <= 6
                && abs(frame.height - candidate.frame.height) <= 6
        }
    }

    private func frame(of axWindow: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAXValue = positionValue,
              let sizeAXValue = sizeValue else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

private struct ScreenshotWindowCandidate: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
}

private final class ScreenshotOverlayWindow: NSWindow {
    let displayID: CGDirectDisplayID

    init(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        screenshot: CGImage,
        windowCandidates: [ScreenshotWindowCandidate],
        preselectedWindowFrame: CGRect?,
        autoTranslateAfterSelection: Bool,
        onSelectWindow: @escaping (ScreenshotWindowCandidate) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onTranslate: @escaping (NSImage, @escaping (Result<ScreenshotTranslationResult, Error>) -> Void) -> Void,
        onSaved: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void
    ) {
        self.displayID = displayID
        let content = ScreenshotOverlayView(
            screen: screen,
            displayID: displayID,
            screenshot: screenshot,
            windowCandidates: windowCandidates,
            preselectedWindowFrame: preselectedWindowFrame,
            autoTranslateAfterSelection: autoTranslateAfterSelection,
            onSelectWindow: onSelectWindow,
            onCopy: onCopy,
            onOCR: onOCR,
            onTranslate: onTranslate,
            onSaved: onSaved,
            onCancel: onCancel,
            onStatus: onStatus
        )
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.contentView = content
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hasShadow = false
        self.acceptsMouseMovedEvents = true
        self.sharingType = .none
        self.makeFirstResponder(content)
    }

    override var canBecomeKey: Bool { true }

    func setWindowRecapturePending(_ isPending: Bool) {
        (contentView as? ScreenshotOverlayView)?.setWindowRecapturePending(isPending)
    }

    func replaceScreenshot(
        _ screenshot: CGImage,
        windowCandidates: [ScreenshotWindowCandidate],
        preselectedWindowFrame: CGRect?
    ) {
        (contentView as? ScreenshotOverlayView)?.replaceScreenshot(
            screenshot,
            windowCandidates: windowCandidates,
            preselectedWindowFrame: preselectedWindowFrame
        )
    }
}

private final class ScreenshotOverlayView: NSView, NSTextFieldDelegate {
    private enum ToolAction: CaseIterable {
        case copy
        case save
        case ocr
        case translate
        case annotate
        case rectangle
        case arrow
        case pen
        case text
        case undo
        case done
        case cancel

        var title: String {
            switch self {
            case .copy: return "复制"
            case .save: return "保存本地"
            case .ocr: return "OCR"
            case .translate: return "翻译"
            case .annotate: return "标注"
            case .rectangle: return "矩形"
            case .arrow: return "箭头"
            case .pen: return "画笔"
            case .text: return "文字"
            case .undo: return "撤销"
            case .done: return "完成"
            case .cancel: return "取消"
            }
        }

        var symbolName: String {
            switch self {
            case .copy: return "doc.on.doc"
            case .save: return "square.and.arrow.down"
            case .ocr: return "text.viewfinder"
            case .translate: return "character.book.closed"
            case .annotate: return "pencil.and.outline"
            case .rectangle: return "rectangle"
            case .arrow: return "arrow.up.right"
            case .pen: return "pencil.tip"
            case .text: return "textformat"
            case .undo: return "arrow.uturn.backward"
            case .done: return "checkmark"
            case .cancel: return "xmark"
            }
        }

        var isAnnotationTool: Bool {
            switch self {
            case .rectangle, .arrow, .pen, .text:
                return true
            case .copy, .save, .ocr, .translate, .annotate, .undo, .done, .cancel:
                return false
            }
        }

        var isEnabled: Bool {
            switch self {
            case .copy, .save, .ocr, .translate, .annotate, .rectangle, .arrow, .pen, .text, .undo, .done, .cancel:
                return true
            }
        }
    }

    private enum AnnotationTool {
        case rectangle
        case arrow
        case pen
        case text
    }

    private struct TranslationPatch {
        let rect: NSRect
        let color: NSColor
    }

    private struct TranslationBlock {
        let text: String
        let rect: NSRect
        let patches: [TranslationPatch]
    }

    private struct TranslationGroup {
        let backdrop: TranslationPatch
        let blocks: [TranslationBlock]
    }

    private enum Markup {
        case rectangle(NSRect)
        case arrow(NSPoint, NSPoint)
        case pen([NSPoint])
        case text(String, NSPoint)
        case translation(TranslationGroup)
    }

    private enum SelectionHandle: CaseIterable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left
    }

    private enum DragMode {
        case create
        case move(startSelection: NSRect)
        case resize(handle: SelectionHandle, startSelection: NSRect)
        case annotate
        case moveMarkup(index: Int, startPoint: NSPoint, original: Markup)
        case pendingWindowSelect(ScreenshotWindowCandidate)
    }

    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let displayBounds: CGRect
    private var screenshot: CGImage
    private var windowCandidates: [ScreenshotWindowCandidate]
    private let autoTranslateAfterSelection: Bool
    private let onSelectWindow: (ScreenshotWindowCandidate) -> Void
    private let onCopy: (NSImage) -> Void
    private let onOCR: (NSImage) -> Void
    private let onTranslate: (NSImage, @escaping (Result<ScreenshotTranslationResult, Error>) -> Void) -> Void
    private let onSaved: (URL) -> Void
    private let onCancel: () -> Void
    private let onStatus: (String, String, MainViewController.PrimaryStatusTone) -> Void
    private var dragStart: NSPoint?
    private var dragMode: DragMode?
    private var selection: NSRect = .zero
    private var hoveredAction: ToolAction?
    private var pressedToolbarAction: ToolAction?
    private var hoveredHandle: SelectionHandle?
    private var hoveredWindowCandidate: ScreenshotWindowCandidate?
    private var lastToolbarRects: [ToolAction: NSRect] = [:]
    private var lastHandleRects: [SelectionHandle: NSRect] = [:]
    private var isAnnotating = false
    private var annotationTool: AnnotationTool = .rectangle
    private var markups: [Markup] = []
    private var selectedMarkupIndex: Int?
    private var activeMarkupStart: NSPoint?
    private var activeMarkupPoint: NSPoint?
    private var activePenPoints: [NSPoint] = []
    private var activeTextField: NSTextField?
    private var activeTextOrigin: NSPoint?
    private var isTranslating = false
    private var isWindowRecapturePending = false
    private var hasAutoTranslatedSelection = false
    private var isSelectionLocked = false
    private let clickDragThreshold: CGFloat = 4

    init(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        screenshot: CGImage,
        windowCandidates: [ScreenshotWindowCandidate],
        preselectedWindowFrame: CGRect?,
        autoTranslateAfterSelection: Bool,
        onSelectWindow: @escaping (ScreenshotWindowCandidate) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onTranslate: @escaping (NSImage, @escaping (Result<ScreenshotTranslationResult, Error>) -> Void) -> Void,
        onSaved: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void
    ) {
        self.screen = screen
        self.displayID = displayID
        self.displayBounds = CGDisplayBounds(displayID)
        self.screenshot = screenshot
        self.windowCandidates = windowCandidates
        self.autoTranslateAfterSelection = autoTranslateAfterSelection
        self.onSelectWindow = onSelectWindow
        self.onCopy = onCopy
        self.onOCR = onOCR
        self.onTranslate = onTranslate
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onStatus = onStatus
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        if let preselectedWindowFrame {
            selection = localWindowRect(for: preselectedWindowFrame) ?? .zero
            isSelectionLocked = hasUsableSelection
        }
        wantsLayer = true
        if autoTranslateAfterSelection, hasUsableSelection {
            DispatchQueue.main.async { [weak self] in
                self?.translateSelectionIfNeeded()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        guard hasUsableSelection else {
            drawHoveredWindowSelection()
            drawInstruction()
            return
        }

        if let cropped = cropSelection() {
            NSImage(cgImage: cropped, size: selection.size).draw(in: selection)
        }
        drawSelectionTint()
        drawMarkups()
        drawActiveMarkup()
        let border = NSBezierPath(rect: selection)
        NSColor.black.withAlphaComponent(0.62).setStroke()
        border.lineWidth = 4
        border.stroke()
        NSColor.white.setStroke()
        border.lineWidth = 2
        border.stroke()
        if !isAnnotating && !isSelectionLocked {
            drawHandles()
            drawSizeLabel()
        } else {
            lastHandleRects = [:]
        }
        drawToolbar()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isWindowRecapturePending else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2, hasUsableSelection, selection.contains(point) {
            if activeTextField != nil {
                commitActiveTextField()
            }
            copySelection()
            return
        }
        if let action = action(at: point), hasUsableSelection {
            pressedToolbarAction = action
            hoveredAction = action
            needsDisplay = true
            return
        }
        if activeTextField != nil {
            commitActiveTextField()
        }
        if isAnnotating, hasUsableSelection, selection.contains(point) {
            let localPoint = localPoint(from: point)
            if let index = markupIndex(at: localPoint) {
                selectedMarkupIndex = index
                dragStart = point
                dragMode = .moveMarkup(index: index, startPoint: localPoint, original: markups[index])
                needsDisplay = true
                return
            }
            beginMarkup(at: point)
            return
        }
        if isSelectionLocked, hasUsableSelection {
            return
        }
        let currentWindowCandidate = hoveredWindowCandidate ?? (!hasUsableSelection ? windowCandidate(at: point) : nil)
        if !hasUsableSelection,
           let windowCandidate = currentWindowCandidate,
           let windowSelection = localWindowRect(for: windowCandidate),
           windowSelection.contains(point) {
            dragStart = point
            dragMode = .pendingWindowSelect(windowCandidate)
            return
        }
        if let handle = handle(at: point), canAdjustSelection {
            dragStart = point
            dragMode = .resize(handle: handle, startSelection: selection)
            return
        }
        if selection.contains(point), canAdjustSelection {
            dragStart = point
            dragMode = .move(startSelection: selection)
            return
        }
        dragStart = point
        dragMode = .create
        selection = NSRect(origin: point, size: .zero)
        isSelectionLocked = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isWindowRecapturePending else { return }
        if let pressedToolbarAction {
            let point = convert(event.locationInWindow, from: nil)
            let action = action(at: point)
            let nextHoveredAction = action == pressedToolbarAction ? action : nil
            if hoveredAction != nextHoveredAction {
                hoveredAction = nextHoveredAction
                needsDisplay = true
            }
            return
        }
        guard let dragStart else { return }
        let current = clamped(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .create, nil:
            guard !isSelectionLocked else { return }
            selection = normalizedRect(from: dragStart, to: current)
            markups.removeAll()
            hasAutoTranslatedSelection = false
        case .move(let startSelection):
            guard !isSelectionLocked else { return }
            let movedSelection = moved(startSelection, from: dragStart, to: current)
            selection = movedSelection
        case .resize(let handle, let startSelection):
            guard !isSelectionLocked else { return }
            selection = resized(startSelection, handle: handle, to: current)
            markups.removeAll()
            hasAutoTranslatedSelection = false
        case .annotate:
            updateMarkup(to: current)
        case .moveMarkup(let index, let startPoint, let original):
            let localPoint = localPoint(from: clamped(current, to: selection))
            if markups.indices.contains(index) {
                markups[index] = moved(original, dx: localPoint.x - startPoint.x, dy: localPoint.y - startPoint.y)
            }
        case .pendingWindowSelect:
            if distance(from: dragStart, to: current) >= clickDragThreshold {
                guard !isSelectionLocked else { return }
                dragMode = .create
                selection = normalizedRect(from: dragStart, to: current)
                markups.removeAll()
                hasAutoTranslatedSelection = false
            }
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isWindowRecapturePending else { return }
        let point = convert(event.locationInWindow, from: nil)
        let action = action(at: point)
        let handle = isSelectionLocked ? nil : handle(at: point)
        let windowCandidate = hasUsableSelection ? nil : windowCandidate(at: point)
        if action != hoveredAction || handle != hoveredHandle || windowCandidate != hoveredWindowCandidate {
            hoveredAction = action
            hoveredHandle = handle
            hoveredWindowCandidate = windowCandidate
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !isWindowRecapturePending else { return }
        if let pressedToolbarAction {
            let point = convert(event.locationInWindow, from: nil)
            let releasedAction = action(at: point)
            self.pressedToolbarAction = nil
            hoveredAction = releasedAction
            if releasedAction == pressedToolbarAction {
                perform(pressedToolbarAction)
            } else {
                needsDisplay = true
            }
            return
        }
        guard let startPoint = dragStart else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        if case .pendingWindowSelect(let candidate) = dragMode,
           distance(from: startPoint, to: point) < clickDragThreshold {
            self.dragStart = nil
            dragMode = nil
            onSelectWindow(candidate)
            return
        }
        if case .annotate = dragMode {
            finishMarkup()
        }
        dragStart = nil
        dragMode = nil
        if !hasUsableSelection {
            selection = .zero
        } else if autoTranslateAfterSelection {
            isSelectionLocked = true
            translateSelectionIfNeeded()
        } else {
            translateSelectionIfNeeded()
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if isWindowRecapturePending {
            if event.keyCode == 53 {
                onCancel()
            }
            return
        }
        if activeTextField != nil {
            super.keyDown(with: event)
            return
        }
        if isAnnotating,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            undoMarkup()
            return
        }
        switch event.keyCode {
        case 36:
            if hasUsableSelection {
                copySelection()
            }
        case 1 where event.modifierFlags.contains(.command):
            saveSelection()
        case 51 where isAnnotating, 117 where isAnnotating:
            deleteSelectedOrUndoMarkup()
        case 53:
            onCancel()
        default:
            super.keyDown(with: event)
        }
    }

    private var hasUsableSelection: Bool {
        selection.width >= 8 && selection.height >= 8
    }

    private var canAdjustSelection: Bool {
        hasUsableSelection && !isSelectionLocked
    }

    private func drawInstruction() {
        let text = hoveredWindowCandidate == nil
            ? "拖拽选择截图区域 · 悬停窗口后单击可选中窗口 · 右键/Esc 取消"
            : "单击选中窗口 · 截图后区域固定 · 右键/Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private func drawHoveredWindowSelection() {
        guard let candidate = hoveredWindowCandidate,
              let rect = localWindowRect(for: candidate) else { return }
        if let cropped = crop(rect) {
            NSImage(cgImage: cropped, size: rect.size).draw(in: rect)
        }
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.62).setStroke()
        path.lineWidth = 5
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 3
        path.stroke()

        let label = "点击选择窗口"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: rect.minX,
            y: max(8, rect.minY - size.height - 14),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }

    private func drawSelectionTint() {
        let path = NSBezierPath(rect: selection)
        NSColor.black.withAlphaComponent(0.08).setFill()
        path.fill()
    }

    private func drawSizeLabel() {
        let scale = pixelScale
        let text = "\(Int(selection.width * scale)) x \(Int(selection.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: selection.minX,
            y: max(8, selection.minY - textSize.height - 14),
            width: textSize.width + 16,
            height: textSize.height + 8
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: NSPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }

    private func drawHandles() {
        var rects: [SelectionHandle: NSRect] = [:]
        for handle in SelectionHandle.allCases {
            let rect = handleRect(handle)
            rects[handle] = rect
            (hoveredHandle == handle ? NSColor.black : NSColor.white).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
        }
        lastHandleRects = rects
    }

    private func drawToolbar() {
        let annotationActions: [ToolAction] = [.rectangle, .arrow, .pen, .text, .ocr, .translate]
        let functionActions: [ToolAction] = [.copy, .undo, .save, .cancel]
        let buttonWidth: CGFloat = 68
        let buttonHeight: CGFloat = 50
        let spacing: CGFloat = 7
        let separatorWidth: CGFloat = 1
        let groupSpacing: CGFloat = 15
        let actions = annotationActions + functionActions
        let totalWidth =
            CGFloat(actions.count) * buttonWidth
            + CGFloat(actions.count - 2) * spacing
            + groupSpacing * 2
            + separatorWidth
            + 14
        let x = min(max(selection.maxX - totalWidth, 8), bounds.width - totalWidth - 8)
        let y = min(selection.maxY + 10, bounds.height - buttonHeight - 14)
        let toolbarRect = NSRect(x: x, y: y, width: totalWidth, height: buttonHeight + 12)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 7, yRadius: 7).fill()

        var rects: [ToolAction: NSRect] = [:]
        var currentX = toolbarRect.minX + 7
        for action in annotationActions {
            let rect = NSRect(
                x: currentX,
                y: toolbarRect.minY + 6,
                width: buttonWidth,
                height: buttonHeight
            )
            rects[action] = rect
            drawToolbarButton(action, in: rect)
            currentX += buttonWidth + spacing
        }

        currentX += groupSpacing - spacing
        let separatorRect = NSRect(x: currentX, y: toolbarRect.minY + 9, width: separatorWidth, height: buttonHeight - 6)
        NSColor.white.withAlphaComponent(0.22).setFill()
        separatorRect.fill()
        currentX += separatorWidth + groupSpacing

        for action in functionActions {
            let rect = NSRect(
                x: currentX,
                y: toolbarRect.minY + 6,
                width: buttonWidth,
                height: buttonHeight
            )
            rects[action] = rect
            drawToolbarButton(action, in: rect)
            currentX += buttonWidth + spacing
        }

        lastToolbarRects = rects
    }

    private func drawToolbarButton(_ action: ToolAction, in rect: NSRect) {
        let isEffectivelyEnabled = action.isEnabled && !(isTranslating && action == .translate)
        let isHovered = isEffectivelyEnabled && hoveredAction == action
        let isPressed = isHovered && pressedToolbarAction == action
        let isSelectedAnnotationTool =
            isAnnotating && (
                (action == .rectangle && annotationTool == .rectangle) ||
                (action == .arrow && annotationTool == .arrow) ||
                (action == .pen && annotationTool == .pen) ||
                (action == .text && annotationTool == .text)
            )
        let fillColor: NSColor = if !isEffectivelyEnabled {
            NSColor.white.withAlphaComponent(0.06)
        } else if isSelectedAnnotationTool {
            NSColor.white.withAlphaComponent(0.92)
        } else if isPressed {
            NSColor.white.withAlphaComponent(0.34)
        } else if isHovered {
            NSColor.white.withAlphaComponent(0.26)
        } else {
            NSColor.white.withAlphaComponent(0.14)
        }
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let foregroundColor: NSColor = !isEffectivelyEnabled
            ? NSColor.white.withAlphaComponent(0.38)
            : (isSelectedAnnotationTool ? NSColor.black : NSColor.white)
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(imageConfig) {
            let imageRect = NSRect(x: rect.midX - 8, y: rect.minY + 7, width: 16, height: 16)
            tintedSymbolImage(image, color: foregroundColor, size: imageRect.size)?.draw(in: imageRect)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: foregroundColor,
        ]
        let title = isTranslating && action == .translate ? "翻译中" : action.title
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(x: rect.midX - min(size.width, rect.width - 8) / 2, y: rect.maxY - size.height - 6),
            withAttributes: attributes
        )
    }

    private func tintedSymbolImage(_ image: NSImage, color: NSColor, size: NSSize) -> NSImage? {
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceIn)
        tinted.unlockFocus()
        return tinted
    }

    private func action(at point: NSPoint) -> ToolAction? {
        lastToolbarRects.first { action, rect in
            action.isEnabled && !(isTranslating && action == .translate) && rect.contains(point)
        }?.key
    }

    private func handle(at point: NSPoint) -> SelectionHandle? {
        lastHandleRects.first { $0.value.contains(point) }?.key
    }

    private func perform(_ action: ToolAction) {
        if activeTextField != nil, action != .cancel {
            commitActiveTextField()
        }
        switch action {
        case .copy:
            copySelection()
        case .save:
            saveSelection()
        case .ocr:
            guard let image = selectedImage() else {
                onStatus("无法识别截图", "未能读取选区截图，请检查屏幕录制权限", .error)
                return
            }
            onOCR(image)
        case .translate:
            translateSelection()
        case .annotate:
            isAnnotating = true
            annotationTool = .rectangle
            onStatus("截图标注", "可直接在截图框内添加矩形、箭头、画笔和文字", .processing)
            needsDisplay = true
        case .rectangle:
            selectAnnotationTool(.rectangle)
        case .arrow:
            selectAnnotationTool(.arrow)
        case .pen:
            selectAnnotationTool(.pen)
        case .text:
            selectAnnotationTool(.text)
        case .undo:
            undoMarkup()
        case .done:
            copySelection()
        case .cancel:
            onCancel()
        }
    }

    private func translateSelection() {
        guard !isTranslating else { return }
        guard let image = selectedImage() else {
            onStatus("无法翻译截图", "未能读取选区截图，请检查屏幕录制权限", .error)
            return
        }
        isTranslating = true
        hoveredAction = nil
        onStatus("截图翻译中", "正在识别选区英文内容", .processing)
        needsDisplay = true
        onTranslate(image) { [weak self] result in
            guard let self else { return }
            self.isTranslating = false
            switch result {
            case .success(let translation):
                guard !translation.translatedLines.isEmpty else {
                    self.onStatus("截图翻译失败", "翻译结果为空，请稍后重试", .warning)
                    self.needsDisplay = true
                    return
                }
                guard let group = self.translationGroup(for: translation.translatedLines) else {
                    self.onStatus("截图翻译失败", "未能定位原文位置，请稍后重试", .warning)
                    self.needsDisplay = true
                    return
                }
                self.markups.append(.translation(group))
                self.selectedMarkupIndex = self.markups.indices.last
                self.isAnnotating = true
                self.onStatus("翻译已覆盖", "已按原文位置贴入中文译文", .success)
            case .failure(let error):
                if case ScreenshotTranslationError.emptyOCR = error {
                    self.onStatus("未识别到文字", Self.translationErrorMessage(error), .warning)
                } else {
                    self.onStatus("截图翻译失败", Self.translationErrorMessage(error), .error)
                }
            }
            self.needsDisplay = true
        }
    }

    private func translateSelectionIfNeeded() {
        guard autoTranslateAfterSelection, !hasAutoTranslatedSelection, hasUsableSelection else { return }
        hasAutoTranslatedSelection = true
        translateSelection()
    }

    private static func translationErrorMessage(_ error: Error) -> String {
        if case ScreenshotTranslationError.emptyOCR = error {
            return "可以调整截图范围后再试一次"
        }
        if case DeepSeekRewriteError.missingAPIKey = error {
            return "请先设置 DeepSeek API Key"
        }
        if case SmartRewriteError.costLimitExceeded(let reason) = error {
            return "已暂停截图翻译：\(reason)"
        }
        return "保留截图选区，可重试或保存原图"
    }

    private func selectAnnotationTool(_ tool: AnnotationTool) {
        isAnnotating = true
        annotationTool = tool
        selectedMarkupIndex = nil
        onStatus("截图标注", "在截图框内直接添加和调整标注", .processing)
        needsDisplay = true
    }

    private func copySelection() {
        guard let image = renderedSelectionImage() else {
            onStatus("无法复制截图", "未能读取选区截图，请检查屏幕录制权限", .error)
            return
        }
        onCopy(image)
    }

    private func selectedImage() -> NSImage? {
        guard let cropped = cropSelection() else { return nil }
        return NSImage(cgImage: cropped, size: selection.size)
    }

    private func renderedSelectionImage() -> NSImage? {
        guard let cropped = cropSelection() else { return nil }
        let image = NSImage(size: selection.size)
        image.lockFocusFlipped(true)
        NSImage(cgImage: cropped, size: selection.size).draw(
            in: NSRect(origin: .zero, size: selection.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        for markup in markups {
            draw(markup, offset: .zero)
        }
        image.unlockFocus()
        return image
    }

    private func saveSelection() {
        guard let image = renderedSelectionImage() else {
            onStatus("无法保存截图", "未能读取选区截图，请检查屏幕录制权限", .error)
            return
        }
        guard let data = image.pngData else {
            onStatus("无法保存截图", "未能生成 PNG 文件", .error)
            return
        }

        do {
            let url = try writeScreenshotData(data, to: ScreenshotSaveLocationStore.directory)
            onSaved(url)
        } catch {
            onStatus("无法保存截图", error.localizedDescription, .error)
        }
    }

    private func writeScreenshotData(_ data: Data, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = availableScreenshotURL(in: directory)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func availableScreenshotURL(in directory: URL) -> URL {
        let baseName = "TW-Shot-\(Self.timestamp())"
        var candidate = directory.appendingPathComponent("\(baseName).png")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).png")
            index += 1
        }
        return candidate
    }

    private var pixelScale: CGFloat {
        CGFloat(screenshot.width) / max(bounds.width, 1)
    }

    private func cropSelection() -> CGImage? {
        crop(selection)
    }

    private func crop(_ rect: NSRect) -> CGImage? {
        let scale = pixelScale
        let crop = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        return screenshot.cropping(to: crop)
    }

    private func windowCandidate(at point: NSPoint) -> ScreenshotWindowCandidate? {
        windowCandidates.first { candidate in
            guard let rect = localWindowRect(for: candidate) else { return false }
            return rect.contains(point)
        }
    }

    private func localWindowRect(for candidate: ScreenshotWindowCandidate) -> NSRect? {
        localWindowRect(for: candidate.frame)
    }

    private func localWindowRect(for frame: CGRect) -> NSRect? {
        let visibleFrame = frame.intersection(displayBounds)
        guard !visibleFrame.isNull,
              visibleFrame.width >= 24,
              visibleFrame.height >= 24 else {
            return nil
        }
        let localRect = NSRect(
            x: visibleFrame.minX - displayBounds.minX,
            y: visibleFrame.minY - displayBounds.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        ).intersection(bounds)
        guard localRect.width >= 24, localRect.height >= 24 else {
            return nil
        }
        return localRect
    }

    func setWindowRecapturePending(_ isPending: Bool) {
        isWindowRecapturePending = isPending
        if isPending {
            pressedToolbarAction = nil
            dragStart = nil
            dragMode = nil
        }
    }

    func replaceScreenshot(
        _ screenshot: CGImage,
        windowCandidates: [ScreenshotWindowCandidate],
        preselectedWindowFrame: CGRect?
    ) {
        discardActiveTextField()
        self.screenshot = screenshot
        self.windowCandidates = windowCandidates
        selection = preselectedWindowFrame.flatMap { localWindowRect(for: $0) } ?? .zero
        isSelectionLocked = hasUsableSelection
        isWindowRecapturePending = false
        isAnnotating = false
        annotationTool = .rectangle
        markups.removeAll()
        selectedMarkupIndex = nil
        activeMarkupStart = nil
        activeMarkupPoint = nil
        activePenPoints = []
        activeTextOrigin = nil
        hoveredAction = nil
        pressedToolbarAction = nil
        hoveredHandle = nil
        hoveredWindowCandidate = nil
        dragStart = nil
        dragMode = nil
        isTranslating = false
        hasAutoTranslatedSelection = false
        needsDisplay = true
        if autoTranslateAfterSelection, hasUsableSelection {
            DispatchQueue.main.async { [weak self] in
                self?.translateSelectionIfNeeded()
            }
        }
    }

    private func pngData(from image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .png, properties: [:])
    }

    private func beginMarkup(at point: NSPoint) {
        let localPoint = localPoint(from: point)
        dragStart = point
        dragMode = .annotate
        switch annotationTool {
        case .text:
            dragStart = nil
            dragMode = nil
            promptForText(at: localPoint)
        case .pen:
            activePenPoints = [localPoint]
        case .rectangle, .arrow:
            activeMarkupStart = localPoint
            activeMarkupPoint = localPoint
        }
        needsDisplay = true
    }

    private func updateMarkup(to point: NSPoint) {
        let localPoint = localPoint(from: clamped(point, to: selection))
        switch annotationTool {
        case .pen:
            activePenPoints.append(localPoint)
        case .rectangle, .arrow:
            activeMarkupPoint = localPoint
        case .text:
            break
        }
    }

    private func finishMarkup() {
        switch annotationTool {
        case .rectangle:
            if let start = activeMarkupStart, let point = activeMarkupPoint {
                let rect = normalizedRect(from: start, to: point)
                if rect.width >= 4, rect.height >= 4 { markups.append(.rectangle(rect)) }
            }
        case .arrow:
            if let start = activeMarkupStart, let point = activeMarkupPoint, distance(from: start, to: point) >= 6 {
                markups.append(.arrow(start, point))
            }
        case .pen:
            if activePenPoints.count > 1 { markups.append(.pen(activePenPoints)) }
        case .text:
            break
        }
        if !markups.isEmpty {
            selectedMarkupIndex = markups.indices.last
        }
        activeMarkupStart = nil
        activeMarkupPoint = nil
        activePenPoints = []
    }

    private func undoMarkup() {
        if !activePenPoints.isEmpty || activeMarkupStart != nil {
            activeMarkupStart = nil
            activeMarkupPoint = nil
            activePenPoints = []
        } else if !markups.isEmpty {
            markups.removeLast()
        }
        selectedMarkupIndex = nil
        needsDisplay = true
    }

    private func deleteSelectedOrUndoMarkup() {
        if let selectedMarkupIndex, markups.indices.contains(selectedMarkupIndex) {
            markups.remove(at: selectedMarkupIndex)
            self.selectedMarkupIndex = nil
        } else {
            undoMarkup()
            return
        }
        needsDisplay = true
    }

    private func drawMarkups() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        for (index, markup) in markups.enumerated() {
            draw(markup, offset: selection.origin)
            if selectedMarkupIndex == index {
                drawSelectionOutline(for: markup, offset: selection.origin)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawActiveMarkup() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        switch annotationTool {
        case .rectangle:
            if let start = activeMarkupStart, let point = activeMarkupPoint {
                draw(.rectangle(normalizedRect(from: start, to: point)), offset: selection.origin)
            }
        case .arrow:
            if let start = activeMarkupStart, let point = activeMarkupPoint {
                draw(.arrow(start, point), offset: selection.origin)
            }
        case .pen:
            if activePenPoints.count > 1 {
                draw(.pen(activePenPoints), offset: selection.origin)
            }
        case .text:
            break
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ markup: Markup, offset: NSPoint) {
        let transformPoint: (NSPoint) -> NSPoint = { point in
            NSPoint(x: point.x + offset.x, y: point.y + offset.y)
        }
        let transformRect: (NSRect) -> NSRect = { rect in
            NSRect(x: rect.minX + offset.x, y: rect.minY + offset.y, width: rect.width, height: rect.height)
        }
        switch markup {
        case .rectangle(let rect):
            let path = NSBezierPath(roundedRect: transformRect(rect), xRadius: 4, yRadius: 4)
            NSColor.systemRed.setStroke()
            path.lineWidth = 3
            path.stroke()
        case .arrow(let start, let end):
            drawArrow(from: transformPoint(start), to: transformPoint(end), lineWidth: 3)
        case .pen(let points):
            guard points.count > 1 else { return }
            let path = NSBezierPath()
            path.move(to: transformPoint(points[0]))
            points.dropFirst().forEach { path.line(to: transformPoint($0)) }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.lineWidth = 3
            NSColor.systemRed.setStroke()
            path.stroke()
        case .text(let text, let point):
            drawText(text, at: transformPoint(point))
        case .translation(let group):
            drawTranslationBackdrop(group.backdrop, transformRect: transformRect)
            for block in group.blocks {
                drawTranslation(block.text, in: transformRect(block.rect), patches: block.patches.map {
                    TranslationPatch(rect: transformRect($0.rect), color: $0.color)
                })
            }
        }
    }

    private func drawSelectionOutline(for markup: Markup, offset: NSPoint) {
        let rect = markupBounds(markup).insetBy(dx: -6, dy: -6).offsetBy(dx: offset.x, dy: offset.y)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func drawArrow(from start: NSPoint, to end: NSPoint, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        NSColor.systemRed.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = max(14, lineWidth * 5)
        let wing: CGFloat = .pi / 7
        let left = NSPoint(x: end.x - cos(angle - wing) * headLength, y: end.y - sin(angle - wing) * headLength)
        let right = NSPoint(x: end.x - cos(angle + wing) * headLength, y: end.y - sin(angle + wing) * headLength)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.move(to: end)
        head.line(to: right)
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.stroke()
    }

    private func drawText(_ text: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let rect = NSRect(x: point.x, y: point.y, width: size.width + padding * 2, height: size.height + padding * 1.5)
        NSColor.white.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: rect.minX + padding, y: rect.minY + padding * 0.55), withAttributes: attributes)
    }

    private func drawTranslationBackdrop(_ patch: TranslationPatch, transformRect: (NSRect) -> NSRect) {
        let rect = transformRect(patch.rect)
        fillFeathered(rect, radius: 7, color: patch.color, coreAlpha: 0.96)
    }

    private func drawTranslation(_ text: String, in rect: NSRect, patches: [TranslationPatch]) {
        for patch in patches {
            fillFeathered(patch.rect, radius: 3, color: patch.color, coreAlpha: 0.94)
        }

        let backgroundColor = patches.last?.color ?? NSColor(calibratedWhite: 0.96, alpha: 1)
        fillFeathered(rect, radius: 5, color: backgroundColor, coreAlpha: 0.88)

        let inset = translationTextInset(for: rect)
        let textRect = rect.insetBy(dx: inset, dy: inset)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = rect.height < 90 ? 0.5 : 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: translationFont(fitting: text, in: rect),
            .foregroundColor: readableTextColor(on: backgroundColor),
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    /// 用多层同心圆角矩形模拟“边缘渐变到全透明”的羽化背景：
    /// 中心保持实心保证译文可读，越靠近边缘越透明，消除生硬的方框边缘、自然融入截图。
    private func fillFeathered(_ rect: NSRect, radius: CGFloat, color: NSColor, coreAlpha: CGFloat) {
        let feather = min(7, min(rect.width, rect.height) * 0.45)
        guard feather > 0.5 else {
            color.withAlphaComponent(coreAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return
        }
        let steps = 8
        // 从最内层（实心）向外逐层扩大并降低透明度：合成后中心保持 coreAlpha，最外缘趋近全透明。
        for index in 0..<steps {
            let progress = CGFloat(index) / CGFloat(steps - 1) // 0 → 内层, 1 → 外缘
            let inset = feather * (1 - progress)
            let inner = rect.insetBy(dx: inset, dy: inset)
            guard inner.width > 0, inner.height > 0 else { continue }
            let cornerRadius = max(0, radius - inset)
            color.withAlphaComponent(coreAlpha * (1 - progress)).setFill()
            NSBezierPath(roundedRect: inner, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }

    private func translationGroup(for translatedLines: [ScreenshotTranslatedLine]) -> TranslationGroup? {
        let pairs: [(sourceRect: NSRect, block: TranslationBlock)] = translatedLines.compactMap { line in
            guard !line.text.isEmpty, !line.rect.isEmpty else { return nil }
            let rect = translationRect(alignedWith: line.rect, text: line.text)
            let patches = translationPatches(for: [line.rect], translationRect: rect)
            return (line.rect, TranslationBlock(text: line.text, rect: rect, patches: patches))
        }
        guard !pairs.isEmpty else { return nil }
        let backdropRect = ScreenshotTranslationLayout.backdropRect(
            sourceRects: pairs.map { $0.sourceRect },
            blockRects: pairs.map { $0.block.rect },
            selectionSize: selection.size
        )
        guard !backdropRect.isEmpty else { return nil }
        return TranslationGroup(
            backdrop: TranslationPatch(rect: backdropRect, color: averageScreenshotColor(in: backdropRect)),
            blocks: pairs.map { $0.block }
        )
    }

    private func translationRect(alignedWith lineRect: NSRect, text: String) -> NSRect {
        ScreenshotTranslationLayout.blockRect(
            alignedWith: lineRect,
            text: text,
            selectionSize: selection.size
        )
    }

    private func translationPatches(for lineRects: [NSRect], translationRect: NSRect) -> [TranslationPatch] {
        let paddedLines = lineRects.map {
            $0.insetBy(dx: -2, dy: -1).intersection(NSRect(origin: .zero, size: selection.size))
        }.filter { !$0.isEmpty }
        let coverRects = paddedLines + [translationRect]
        return coverRects.map { rect in
            TranslationPatch(rect: rect, color: averageScreenshotColor(in: rect))
        }
    }

    private func unionRect(_ rects: [NSRect]) -> NSRect? {
        rects.reduce(nil) { partial, rect in
            guard !rect.isEmpty else { return partial }
            return partial?.union(rect) ?? rect
        }
    }

    private func averageScreenshotColor(in localRect: NSRect) -> NSColor {
        let absoluteRect = NSRect(
            x: selection.minX + localRect.minX,
            y: selection.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        ).intersection(selection)
        guard let image = crop(absoluteRect) else {
            return NSColor(calibratedWhite: 0.96, alpha: 1)
        }
        return Self.averageColor(in: image) ?? NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    private func readableTextColor(on backgroundColor: NSColor) -> NSColor {
        let color = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        let luminance = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return luminance < 0.56 ? .white : .black
    }

    private func translationFont(fitting text: String, in rect: NSRect) -> NSFont {
        let fontSize = translationFontSize(fitting: text, width: rect.width, maxHeight: max(1, rect.height))
        return .systemFont(ofSize: fontSize, weight: .semibold)
    }

    private func translationFontSize(fitting text: String, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        ScreenshotTranslationLayout.fontSize(
            fitting: text,
            width: width,
            maxHeight: maxHeight,
            selectionSize: selection.size
        )
    }

    private func translationTextHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        ScreenshotTranslationLayout.textHeight(
            text,
            width: width,
            fontSize: fontSize,
            selectionSize: selection.size
        )
    }

    private func translationTextInset(for rect: NSRect) -> CGFloat {
        ScreenshotTranslationLayout.textInset(for: rect)
    }

    private static func averageColor(in image: CGImage) -> NSColor? {
        let rep = NSBitmapImageRep(cgImage: image)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let strideX = max(1, width / 16)
        let strideY = max(1, height / 16)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    red += color.redComponent
                    green += color.greenComponent
                    blue += color.blueComponent
                    count += 1
                }
                x += strideX
            }
            y += strideY
        }
        guard count > 0 else { return nil }
        return NSColor(
            calibratedRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: 1
        )
    }

    private func promptForText(at point: NSPoint) {
        commitActiveTextField()
        let origin = localPoint(from: NSPoint(x: point.x + selection.minX, y: point.y + selection.minY))
        activeTextOrigin = origin

        let fieldWidth = min(max(selection.width - origin.x - 12, 140), 320)
        let fieldRect = NSRect(
            x: selection.minX + origin.x,
            y: selection.minY + origin.y,
            width: fieldWidth,
            height: 30
        )
        let field = NSTextField(frame: fieldRect)
        field.delegate = self
        field.target = self
        field.action = #selector(commitActiveTextFieldFromAction)
        field.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        field.textColor = .black
        field.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.focusRingType = .none
        field.placeholderString = "文字"
        addSubview(field)
        activeTextField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitActiveTextFieldFromAction() {
        commitActiveTextField()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitActiveTextField()
    }

    private func commitActiveTextField() {
        guard let field = activeTextField else { return }
        let origin = activeTextOrigin ?? localPoint(from: field.frame.origin)
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        activeTextField = nil
        activeTextOrigin = nil
        if !text.isEmpty {
            markups.append(.text(text, origin))
            selectedMarkupIndex = markups.indices.last
        }
        needsDisplay = true
    }

    func discardActiveTextField() {
        guard let field = activeTextField else { return }
        field.delegate = nil
        field.removeFromSuperview()
        activeTextField = nil
        activeTextOrigin = nil
    }

    private func localPoint(from point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x - selection.minX, 0), selection.width),
            y: min(max(point.y - selection.minY, 0), selection.height)
        )
    }

    private func clamped(_ point: NSPoint, to rect: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func markupIndex(at point: NSPoint) -> Int? {
        markups.indices.reversed().first { index in
            markupBounds(markups[index]).insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    private func markupBounds(_ markup: Markup) -> NSRect {
        switch markup {
        case .rectangle(let rect):
            return rect
        case .arrow(let start, let end):
            return normalizedRect(from: start, to: end)
        case .pen(let points):
            guard let first = points.first else { return .zero }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text(let text, let point):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            ]
            let size = text.size(withAttributes: attributes)
            return NSRect(x: point.x, y: point.y, width: size.width + 16, height: size.height + 12)
        case .translation(let group):
            let rects = [group.backdrop.rect] + group.blocks.flatMap { [$0.rect] + $0.patches.map(\.rect) }
            return rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
        }
    }

    private func moved(_ markup: Markup, dx: CGFloat, dy: CGFloat) -> Markup {
        func movedPoint(_ point: NSPoint) -> NSPoint {
            NSPoint(
                x: min(max(point.x + dx, 0), selection.width),
                y: min(max(point.y + dy, 0), selection.height)
            )
        }
        func movedRect(_ rect: NSRect) -> NSRect {
            var moved = rect.offsetBy(dx: dx, dy: dy)
            if moved.minX < 0 { moved.origin.x = 0 }
            if moved.minY < 0 { moved.origin.y = 0 }
            if moved.maxX > selection.width { moved.origin.x = max(0, selection.width - moved.width) }
            if moved.maxY > selection.height { moved.origin.y = max(0, selection.height - moved.height) }
            return moved
        }
        switch markup {
        case .rectangle(let rect):
            return .rectangle(rect.offsetBy(dx: dx, dy: dy).intersection(NSRect(origin: .zero, size: selection.size)))
        case .arrow(let start, let end):
            return .arrow(movedPoint(start), movedPoint(end))
        case .pen(let points):
            return .pen(points.map(movedPoint))
        case .text(let text, let point):
            return .text(text, movedPoint(point))
        case .translation(let group):
            return .translation(TranslationGroup(
                backdrop: TranslationPatch(rect: movedRect(group.backdrop.rect), color: group.backdrop.color),
                blocks: group.blocks.map { block in
                    TranslationBlock(
                        text: block.text,
                        rect: movedRect(block.rect),
                        patches: block.patches.map { TranslationPatch(rect: movedRect($0.rect), color: $0.color) }
                    )
                }
            ))
        }
    }

    private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func handleRect(_ handle: SelectionHandle) -> NSRect {
        let size: CGFloat = 9
        let point: NSPoint
        switch handle {
        case .topLeft:
            point = NSPoint(x: selection.minX, y: selection.minY)
        case .top:
            point = NSPoint(x: selection.midX, y: selection.minY)
        case .topRight:
            point = NSPoint(x: selection.maxX, y: selection.minY)
        case .right:
            point = NSPoint(x: selection.maxX, y: selection.midY)
        case .bottomRight:
            point = NSPoint(x: selection.maxX, y: selection.maxY)
        case .bottom:
            point = NSPoint(x: selection.midX, y: selection.maxY)
        case .bottomLeft:
            point = NSPoint(x: selection.minX, y: selection.maxY)
        case .left:
            point = NSPoint(x: selection.minX, y: selection.midY)
        }
        return NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    }

    private func moved(_ rect: NSRect, from start: NSPoint, to end: NSPoint) -> NSRect {
        var moved = rect.offsetBy(dx: end.x - start.x, dy: end.y - start.y)
        if moved.minX < bounds.minX {
            moved.origin.x = bounds.minX
        }
        if moved.minY < bounds.minY {
            moved.origin.y = bounds.minY
        }
        if moved.maxX > bounds.maxX {
            moved.origin.x = bounds.maxX - moved.width
        }
        if moved.maxY > bounds.maxY {
            moved.origin.y = bounds.maxY - moved.height
        }
        return moved
    }

    private func resized(_ rect: NSRect, handle: SelectionHandle, to point: NSPoint) -> NSRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = point.x
            minY = point.y
        case .top:
            minY = point.y
        case .topRight:
            maxX = point.x
            minY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x
            maxY = point.y
        case .bottom:
            maxY = point.y
        case .bottomLeft:
            minX = point.x
            maxY = point.y
        case .left:
            minX = point.x
        }

        return normalizedRect(
            from: NSPoint(x: minX, y: minY),
            to: NSPoint(x: maxX, y: maxY)
        )
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        ).intersection(bounds)
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}

private enum ScreenshotTranslationError: Error {
    case emptyOCR
}

private struct ScreenshotTranslationResult {
    let translatedText: String
    let translatedLines: [ScreenshotTranslatedLine]
}

private struct ScreenshotTranslatedLine {
    let text: String
    let rect: NSRect
}

private struct ScreenshotOCRResult {
    let text: String
    let lines: [ScreenshotOCRLine]
}

private struct ScreenshotOCRLine {
    let text: String
    let rect: NSRect
}

private final class ScreenshotOCRRecognizer {
    func recognize(image: NSImage) async throws -> ScreenshotOCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "TypeWhale.ScreenshotOCR", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法读取截图图像"
            ])
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let imageSize = image.size
                    let lines = observations
                        .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                        .compactMap { observation -> ScreenshotOCRLine? in
                            guard let text = observation.topCandidates(1).first?.string
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                                  !text.isEmpty else { return nil }
                            return ScreenshotOCRLine(
                                text: text,
                                rect: Self.localRect(from: observation.boundingBox, imageSize: imageSize)
                            )
                        }
                    continuation.resume(returning: ScreenshotOCRResult(
                        text: lines.map(\.text).joined(separator: "\n"),
                        lines: lines
                    ))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
                if let supportedLanguages = try? request.supportedRecognitionLanguages() {
                    let availableLanguages = preferredLanguages.filter { supportedLanguages.contains($0) }
                    request.recognitionLanguages = availableLanguages.isEmpty ? ["en-US"] : availableLanguages
                } else {
                    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                }
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func localRect(from normalizedRect: CGRect, imageSize: NSSize) -> NSRect {
        NSRect(
            x: normalizedRect.minX * imageSize.width,
            y: (1 - normalizedRect.maxY) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
