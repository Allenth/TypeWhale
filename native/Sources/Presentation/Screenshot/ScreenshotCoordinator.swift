import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import Vision

@MainActor
final class ScreenshotCoordinator {
    private var overlays: [ScreenshotOverlayWindow] = []
    private var operationGeneration = 0
    private let ocrRecognizer = ScreenshotOCRRecognizer()
    private let onStatus: (String, String, MainViewController.PrimaryStatusTone) -> Void

    init(onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void) {
        self.onStatus = onStatus
    }

    var isActive: Bool {
        !overlays.isEmpty
    }

    func begin() {
        guard !isActive else { return }
        invalidatePendingOperations()
        let screenOverlays = NSScreen.screens.compactMap { screen -> ScreenshotOverlayWindow? in
            guard let image = captureFullScreen(screen) else { return nil }
            return ScreenshotOverlayWindow(
                screen: screen,
                screenshot: image,
                onCopy: { [weak self] image in self?.copy(image) },
                onOCR: { [weak self] image in self?.recognizeText(in: image) },
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
        NSApp.activate(ignoringOtherApps: true)
        overlays.forEach { $0.orderFrontRegardless() }
        // 必须让某个覆盖窗口成为 key window，否则 keyDown（含 Esc）不会传到视图，导致无法用 Esc 退出截图。
        overlays.first?.makeKey()
        onStatus("截图模式", "拖拽选择区域，复制后会写入剪贴板", .processing)
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
        showTransientStatus(
            "截图已保存",
            "已保存到下载文件夹：\(url.lastPathComponent)",
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
                let text = try await ocrRecognizer.recognize(image: image)
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

    private func closeAll() {
        overlays.forEach {
            ($0.contentView as? ScreenshotOverlayView)?.discardActiveTextField()
            $0.orderOut(nil)
        }
        overlays.removeAll()
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

    private func captureFullScreen(_ screen: NSScreen) -> CGImage? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value))
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    init(
        screen: NSScreen,
        screenshot: CGImage,
        onCopy: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onSaved: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void
    ) {
        let content = ScreenshotOverlayView(
            screen: screen,
            screenshot: screenshot,
            onCopy: onCopy,
            onOCR: onOCR,
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
        self.makeFirstResponder(content)
    }

    override var canBecomeKey: Bool { true }
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
            case .copy, .save, .ocr, .annotate, .rectangle, .arrow, .pen, .text, .undo, .done, .cancel:
                return true
            case .translate:
                return false
            }
        }
    }

    private enum AnnotationTool {
        case rectangle
        case arrow
        case pen
        case text
    }

    private enum Markup {
        case rectangle(NSRect)
        case arrow(NSPoint, NSPoint)
        case pen([NSPoint])
        case text(String, NSPoint)
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
    }

    private let screen: NSScreen
    private let screenshot: CGImage
    private let onCopy: (NSImage) -> Void
    private let onOCR: (NSImage) -> Void
    private let onSaved: (URL) -> Void
    private let onCancel: () -> Void
    private let onStatus: (String, String, MainViewController.PrimaryStatusTone) -> Void
    private var dragStart: NSPoint?
    private var dragMode: DragMode?
    private var selection: NSRect = .zero
    private var hoveredAction: ToolAction?
    private var hoveredHandle: SelectionHandle?
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

    init(
        screen: NSScreen,
        screenshot: CGImage,
        onCopy: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onSaved: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onStatus: @escaping (String, String, MainViewController.PrimaryStatusTone) -> Void
    ) {
        self.screen = screen
        self.screenshot = screenshot
        self.onCopy = onCopy
        self.onOCR = onOCR
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onStatus = onStatus
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
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
            drawInstruction()
            return
        }

        if let cropped = cropSelection() {
            NSImage(cgImage: cropped, size: selection.size).draw(in: selection)
        }
        drawMarkups()
        drawActiveMarkup()
        NSColor.systemYellow.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        border.stroke()
        if !isAnnotating {
            drawHandles()
            drawSizeLabel()
        }
        drawToolbar()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if activeTextField != nil {
            commitActiveTextField()
        }
        if event.clickCount >= 2, hasUsableSelection, selection.contains(point), !isAnnotating {
            copySelection()
            return
        }
        if let action = action(at: point), hasUsableSelection {
            perform(action)
            return
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
        if let handle = handle(at: point), hasUsableSelection {
            dragStart = point
            dragMode = .resize(handle: handle, startSelection: selection)
            return
        }
        if selection.contains(point), hasUsableSelection {
            dragStart = point
            dragMode = .move(startSelection: selection)
            return
        }
        dragStart = point
        dragMode = .create
        selection = NSRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = clamped(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .create, nil:
            selection = normalizedRect(from: dragStart, to: current)
            markups.removeAll()
        case .move(let startSelection):
            let movedSelection = moved(startSelection, from: dragStart, to: current)
            selection = movedSelection
        case .resize(let handle, let startSelection):
            selection = resized(startSelection, handle: handle, to: current)
            markups.removeAll()
        case .annotate:
            updateMarkup(to: current)
        case .moveMarkup(let index, let startPoint, let original):
            let localPoint = localPoint(from: clamped(current, to: selection))
            if markups.indices.contains(index) {
                markups[index] = moved(original, dx: localPoint.x - startPoint.x, dy: localPoint.y - startPoint.y)
            }
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let action = action(at: point)
        let handle = handle(at: point)
        if action != hoveredAction || handle != hoveredHandle {
            hoveredAction = action
            hoveredHandle = handle
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        if case .annotate = dragMode {
            finishMarkup()
        }
        dragStart = nil
        dragMode = nil
        if !hasUsableSelection {
            selection = .zero
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
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

    private func drawInstruction() {
        let text = "拖拽选择截图区域 · 右键/Esc 取消"
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
            (hoveredHandle == handle ? NSColor.systemYellow : NSColor.white).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
        }
        lastHandleRects = rects
    }

    private func drawToolbar() {
        let annotationActions: [ToolAction] = [.rectangle, .arrow, .pen, .text, .ocr]
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
        let isHovered = action.isEnabled && hoveredAction == action
        let isSelectedAnnotationTool =
            isAnnotating && (
                (action == .rectangle && annotationTool == .rectangle) ||
                (action == .arrow && annotationTool == .arrow) ||
                (action == .pen && annotationTool == .pen) ||
                (action == .text && annotationTool == .text)
            )
        let fillColor: NSColor = if !action.isEnabled {
            NSColor.white.withAlphaComponent(0.06)
        } else if isSelectedAnnotationTool {
            NSColor.systemYellow.withAlphaComponent(0.92)
        } else if isHovered {
            NSColor.systemYellow.withAlphaComponent(0.95)
        } else {
            NSColor.white.withAlphaComponent(0.14)
        }
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let foregroundColor: NSColor = !action.isEnabled
            ? NSColor.white.withAlphaComponent(0.38)
            : ((isHovered || isSelectedAnnotationTool) ? NSColor.black : NSColor.white)
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
        let size = action.title.size(withAttributes: attributes)
        action.title.draw(
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
            action.isEnabled && rect.contains(point)
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
            onStatus("截图功能待接入", "覆盖翻译将接入中文识别、英文翻译和版面重绘", .warning)
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
            let url = try writeScreenshotData(data, to: ScreenshotSaveLocationStore.defaultDirectory)
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
        let scale = pixelScale
        let crop = CGRect(
            x: selection.minX * scale,
            y: selection.minY * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
        return screenshot.cropping(to: crop)
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
            NSColor.systemYellow.setStroke()
            path.stroke()
        case .text(let text, let point):
            drawText(text, at: transformPoint(point))
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
        NSColor.systemYellow.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: rect.minX + padding, y: rect.minY + padding * 0.55), withAttributes: attributes)
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
        field.backgroundColor = .systemYellow
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
        }
    }

    private func moved(_ markup: Markup, dx: CGFloat, dy: CGFloat) -> Markup {
        func movedPoint(_ point: NSPoint) -> NSPoint {
            NSPoint(
                x: min(max(point.x + dx, 0), selection.width),
                y: min(max(point.y + dy, 0), selection.height)
            )
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

private final class ScreenshotOCRRecognizer {
    func recognize(image: NSImage) async throws -> String {
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
                    let lines = observations
                        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: lines.joined(separator: "\n"))
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
}

private extension NSImage {
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
