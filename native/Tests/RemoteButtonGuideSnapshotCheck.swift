import AppKit
import Foundation

@MainActor
enum AppSettingsStore {
    static var useMistLightTheme = false
}

@MainActor
private final class SnapshotCanvasView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        UITheme.cardFill.setFill()
        dirtyRect.fill()
    }
}

@MainActor
private func luminance(_ color: NSColor) -> CGFloat {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
}

@MainActor
private func maximumLuminance(
    near point: CGPoint,
    radius: Int,
    bitmap: NSBitmapImageRep,
    bounds: CGRect
) -> CGFloat {
    let scaleX = CGFloat(bitmap.pixelsWide) / bounds.width
    let scaleY = CGFloat(bitmap.pixelsHigh) / bounds.height
    let centerX = Int((point.x * scaleX).rounded())
    let centerY = Int((point.y * scaleY).rounded())
    let pixelRadius = max(1, Int((CGFloat(radius) * max(scaleX, scaleY)).rounded()))
    var maximum: CGFloat = 0
    for y in max(0, centerY - pixelRadius)...min(bitmap.pixelsHigh - 1, centerY + pixelRadius) {
        for x in max(0, centerX - pixelRadius)...min(bitmap.pixelsWide - 1, centerX + pixelRadius) {
            if let color = bitmap.colorAt(x: x, y: y) {
                maximum = max(maximum, luminance(color))
            }
        }
    }
    return maximum
}

@MainActor
private func assertPhotoVisible(bitmap: NSBitmapImageRep, bounds: CGRect) throws {
    let bodyRect = XiaomiRemote2ProDiagramSpec.bodyRect(in: bounds)
    let silverBodyPoint = CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.80)
    let maximum = maximumLuminance(
        near: silverBodyPoint,
        radius: 6,
        bitmap: bitmap,
        bounds: bounds
    )
    guard maximum >= 0.48 else {
        throw NSError(
            domain: "RemoteButtonGuideSnapshotCheck",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "RC003 product photo was not visible: \(maximum)"]
        )
    }
}

@MainActor
private func makeSyntheticRemotePhoto() -> NSImage {
    let image = NSImage(size: RemoteControlPhotoResource.expectedPixelSize)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    return image
}

@MainActor
private func render(
    width: CGFloat,
    light: Bool,
    outputURL: URL,
    photo: NSImage,
    verifiesPhoto: Bool = false,
    pressedButton: RemoteButton? = nil
) throws {
    AppSettingsStore.useMistLightTheme = light
    let height = width < XiaomiRemote2ProDiagramSpec.compactBreakpoint
        ? XiaomiRemote2ProDiagramSpec.compactHeight
        : XiaomiRemote2ProDiagramSpec.regularHeight
    let canvas = SnapshotCanvasView(frame: CGRect(x: 0, y: 0, width: width, height: height))
    canvas.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    let guide = RemoteButtonGuideView(frame: canvas.bounds, imageProvider: { photo })
    guide.translatesAutoresizingMaskIntoConstraints = true
    guide.frame = canvas.bounds
    canvas.addSubview(guide)
    guide.apply(mapping: .defaults, pressedButton: pressedButton)
    canvas.layoutSubtreeIfNeeded()
    guide.layoutSubtreeIfNeeded()

    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 1)
    }
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 2)
    }
    try png.write(to: outputURL, options: .atomic)
    guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0, png.count > 10_000 else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 3)
    }
    if verifiesPhoto {
        try assertPhotoVisible(bitmap: bitmap, bounds: canvas.bounds)
    }
}

@MainActor
private func verifyPhysicalPressIntegration(photo: NSImage) throws {
    let guide = RemoteButtonGuideView(
        frame: CGRect(x: 0, y: 0, width: 640, height: 480),
        imageProvider: { photo }
    )
    guide.apply(mapping: .defaults, pressedButton: .back)
    guard guide.activeFeedbackButton == .back else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 19)
    }
    let expected = "刚刚识别：返回键 · 系统返回"
    guard descendants(of: guide).contains(where: {
        $0.isAccessibilityElement() && $0.accessibilityLabel() == expected
    }) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 20)
    }
    guide.apply(mapping: .defaults, pressedButton: nil)
    guard guide.activeFeedbackButton == .back else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 21)
    }
}

@MainActor
private func verifyInterfacePressIntegration(photo: NSImage) throws {
    let mappingView = RemoteButtonMappingView(frame: CGRect(x: 0, y: 0, width: 552, height: 300))
    let guideView = RemoteButtonGuideView(
        frame: CGRect(x: 0, y: 0, width: 640, height: 480),
        imageProvider: { photo }
    )
    mappingView.onButtonPreview = { button in
        guideView.preview(button: button)
    }

    guard let control = popup(for: .power, in: mappingView) as? RemoteButtonPreviewPopUpButton else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 23)
    }
    control.previewButton()
    guard guideView.activeFeedbackButton == .power else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 24)
    }
    let expected = "刚刚识别：电源键 · 系统电源功能"
    guard descendants(of: guideView).contains(where: {
        $0.isAccessibilityElement() && $0.accessibilityLabel() == expected
    }) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 25)
    }
}

@MainActor
private func renderMissingPhoto(outputURL: URL) throws {
    AppSettingsStore.useMistLightTheme = false
    let bounds = CGRect(x: 0, y: 0, width: 220, height: 480)
    let canvas = SnapshotCanvasView(frame: bounds)
    canvas.appearance = NSAppearance(named: .darkAqua)
    let illustration = RemoteControlIllustrationView(frame: bounds, imageProvider: { nil })
    illustration.frame = bounds
    canvas.addSubview(illustration)

    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: bounds) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 15)
    }
    canvas.cacheDisplay(in: bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 16)
    }
    try png.write(to: outputURL, options: .atomic)
    guard png.count > 5_000 else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 17)
    }
}

@MainActor
private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants)
}

@MainActor
private func popup(for button: RemoteButton, in view: NSView) -> NSPopUpButton? {
    let expectedLabel = "\(RemoteButtonPresentation.title(for: button))动作"
    return descendants(of: view)
        .compactMap { $0 as? NSPopUpButton }
        .first { $0.accessibilityLabel() == expectedLabel }
}

@MainActor
private func verifyMappingIntegration() throws {
    let mappingView = RemoteButtonMappingView(frame: CGRect(x: 0, y: 0, width: 552, height: 300))
    let guideView = RemoteButtonGuideView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
    let changes: [(RemoteButton, RemoteButtonAction)] = [
        (.voice, .keyboardEscape),
        (.home, .send),
        (.menu, .cancel),
        (.dpadUp, .none),
        (.volumeUp, .send),
        (.tv, .toggleMainWindow),
        (.power, .cancel),
    ]
    var callbacks: [(RemoteButton, RemoteButtonAction)] = []
    mappingView.onMappingChange = { callbacks.append(($0, $1)) }
    var customized = RemoteButtonMapping.defaults

    for (button, action) in changes {
        let actionID = RemoteActionCatalog.builtIn.binding(for: action).actionID.rawValue
        guard let control = popup(for: button, in: mappingView),
              let item = control.itemArray.first(where: { $0.representedObject as? String == actionID }),
              let actionSelector = control.action else {
            throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 10)
        }
        control.select(item)
        _ = NSApp.sendAction(actionSelector, to: control.target, from: control)
        customized.set(action, for: button)
    }
    guard callbacks.count == changes.count,
          zip(callbacks, changes).allSatisfy({ callback, expected in
              callback.0 == expected.0 && callback.1 == expected.1
          }) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 11)
    }

    mappingView.apply(mapping: customized)
    guideView.apply(mapping: customized)
    for (button, action) in changes {
        let actionID = RemoteActionCatalog.builtIn.binding(for: action).actionID.rawValue
        guard popup(for: button, in: mappingView)?.selectedItem?.representedObject as? String == actionID else {
            throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 12)
        }
        let expectedLabel = "\(RemoteButtonPresentation.title(for: button))，当前功能：\(RemoteButtonPresentation.actionDetail(for: action, button: button))"
        let guideUpdated = descendants(of: guideView).contains {
            $0.isAccessibilityElement() && $0.accessibilityLabel() == expectedLabel
        }
        guard guideUpdated else {
            throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 13)
        }
    }

    mappingView.apply(mapping: .defaults)
    guideView.apply(mapping: .defaults)
    for (button, _) in changes {
        let expected = RemoteButtonMapping.defaults.binding(for: button).actionID.rawValue
        guard popup(for: button, in: mappingView)?.selectedItem?.representedObject as? String == expected else {
            throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 14)
        }
    }
}

@MainActor
private func renderMapping(light: Bool, outputURL: URL) throws {
    AppSettingsStore.useMistLightTheme = light
    let bounds = CGRect(x: 0, y: 0, width: 552, height: 300)
    let canvas = SnapshotCanvasView(frame: bounds)
    canvas.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    let mapping = RemoteButtonMappingView(frame: bounds)
    mapping.translatesAutoresizingMaskIntoConstraints = true
    mapping.frame = bounds
    canvas.addSubview(mapping)
    mapping.apply(mapping: .defaults)
    canvas.layoutSubtreeIfNeeded()
    mapping.layoutSubtreeIfNeeded()

    let popups = descendants(of: mapping).compactMap { $0 as? NSPopUpButton }
    guard popups.count == RemoteButton.allCases.count else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 6)
    }
    guard popup(for: .voice, in: mapping)?.itemArray.contains(where: {
        $0.representedObject as? String == RemoteActionID.pushToTalk.rawValue
    }) == true,
    popup(for: .back, in: mapping)?.itemArray.contains(where: {
        $0.representedObject as? String == RemoteActionID.pushToTalk.rawValue
    }) == false else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 22)
    }
    let visibleBounds = canvas.bounds.insetBy(dx: -1, dy: -1)
    for popup in popups {
        let frame = popup.convert(popup.bounds, to: canvas)
        guard visibleBounds.contains(frame), frame.width >= 120, frame.height >= 20 else {
            throw NSError(
                domain: "RemoteButtonGuideSnapshotCheck",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Mapping control outside visible bounds: \(frame)"]
            )
        }
    }

    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 8)
    }
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 9)
    }
    try png.write(to: outputURL, options: .atomic)
}

@main
struct RemoteButtonGuideSnapshotCheck {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "RemoteButtonGuideSnapshotCheck", code: 4)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let photo = makeSyntheticRemotePhoto()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try render(
            width: 640,
            light: false,
            outputURL: directory.appendingPathComponent("remote-guide-dark-regular.png"),
            photo: photo,
            verifiesPhoto: true
        )
        try render(
            width: 460,
            light: false,
            outputURL: directory.appendingPathComponent("remote-guide-dark-compact.png"),
            photo: photo,
            verifiesPhoto: true
        )
        try render(
            width: 640,
            light: true,
            outputURL: directory.appendingPathComponent("remote-guide-light-regular.png"),
            photo: photo
        )
        try render(
            width: 640,
            light: false,
            outputURL: directory.appendingPathComponent("remote-guide-pressed-back.png"),
            photo: photo,
            pressedButton: .back
        )
        try render(
            width: 460,
            light: true,
            outputURL: directory.appendingPathComponent("remote-guide-light-compact.png"),
            photo: photo
        )
        try renderMissingPhoto(outputURL: directory.appendingPathComponent("remote-guide-missing-photo.png"))
        try renderMapping(light: false, outputURL: directory.appendingPathComponent("remote-mapping-dark.png"))
        try renderMapping(light: true, outputURL: directory.appendingPathComponent("remote-mapping-light.png"))
        try verifyMappingIntegration()
        try verifyPhysicalPressIntegration(photo: photo)
        try verifyInterfacePressIntegration(photo: photo)
        print("RemoteButtonGuideSnapshotCheck passed")
    }
}
