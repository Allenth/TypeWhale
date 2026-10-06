import AppKit
import Foundation

@main
struct RemoteButtonGuideSpecCheck {
    static func main() {
        let items = XiaomiRemote2ProDiagramSpec.items
        precondition(items.count == RemoteButton.allCases.count)
        precondition(Set(items.map(\.button)) == Set(RemoteButton.allCases))

        let left = items.filter { $0.side == .left }.sorted { $0.order < $1.order }
        let right = items.filter { $0.side == .right }.sorted { $0.order < $1.order }
        precondition(left.count == 6)
        precondition(right.count == 7)
        precondition(left.map(\.order) == Array(0..<left.count))
        precondition(right.map(\.order) == Array(0..<right.count))
        precondition(left.map(\.button) == [
            .power, .dpadUp, .dpadLeft, .back, .home, .menu,
        ])
        precondition(right.map(\.button) == [
            .voice, .dpadRight, .center, .dpadDown, .volumeUp, .volumeDown, .tv,
        ])

        func anchor(_ button: RemoteButton) -> CGPoint {
            guard let item = items.first(where: { $0.button == button }) else {
                preconditionFailure("Missing diagram item for \(button)")
            }
            return item.anchor
        }

        precondition(anchor(.power).x < anchor(.voice).x)
        precondition(anchor(.back).y < anchor(.home).y)
        precondition(anchor(.home).y < anchor(.menu).y)
        precondition(anchor(.volumeUp).x > anchor(.back).x)
        precondition(anchor(.volumeUp).y < anchor(.volumeDown).y)
        precondition(anchor(.menu).x < anchor(.tv).x)

        for item in items {
            precondition((0...1).contains(item.anchor.x))
            precondition((0...1).contains(item.anchor.y))
            precondition((0...1).contains(item.calloutY))
        }

        let pressRegions = RemoteButtonPressVisualSpec.regions
        precondition(pressRegions.count == RemoteButton.allCases.count)
        precondition(Set(pressRegions.map(\.button)) == Set(RemoteButton.allCases))
        for region in pressRegions {
            precondition((0...1).contains(region.normalizedRect.minX))
            precondition((0...1).contains(region.normalizedRect.minY))
            precondition((0...1).contains(region.normalizedRect.maxX))
            precondition((0...1).contains(region.normalizedRect.maxY))
            precondition(region.normalizedRect.width > 0)
            precondition(region.normalizedRect.height > 0)
        }

        let editable = RemoteButtonPresentation.editableButtons(
            supportedButtons: XiaomiRemote2ProHIDProfile.supportedButtons
        )
        precondition(editable.count == RemoteButton.allCases.count)
        precondition(editable.contains(.voice))
        precondition(Set(editable) == Set(RemoteButton.allCases))

        for button in RemoteButton.allCases {
            let grouped = RemoteButtonActionPresentation.groups(for: button).flatMap(\.actions)
            precondition(Set(grouped) == Set(RemoteButtonAction.allowedActions(for: button)))
            precondition(grouped.count == Set(grouped).count)
        }
        let voiceGroups = RemoteButtonActionPresentation.groups(for: .voice)
        precondition(voiceGroups.map(\.title) == ["默认", "键盘", "TypeWhale", "Mac", "关闭"])
        precondition(voiceGroups.flatMap(\.actions) == [
            .pushToTalk,
            .system,
            .keyboardEscape,
            .keyboardDelete,
            .keyboardReturn,
            .toggleMainWindow,
            .send,
            .cancel,
            .lockMac,
            .none,
        ])
        let backGroups = RemoteButtonActionPresentation.groups(for: .back)
        precondition(backGroups.map(\.title) == ["默认", "键盘", "TypeWhale", "Mac", "关闭"])
        precondition(backGroups.flatMap(\.actions) == [
            .system,
            .keyboardEscape,
            .keyboardDelete,
            .keyboardReturn,
            .toggleMainWindow,
            .send,
            .cancel,
            .lockMac,
            .none,
        ])

        for button in RemoteButton.allCases {
            precondition(!RemoteButtonPresentation.title(for: button).isEmpty)
            let detail = RemoteButtonPresentation.actionDetail(
                for: RemoteButtonMapping.defaults.action(for: button),
                button: button
            )
            precondition(!detail.isEmpty)
        }

        precondition(RemoteButtonPresentation.actionDetail(for: .system, button: .dpadUp) == "系统导航")
        precondition(RemoteButtonPresentation.actionDetail(for: .system, button: .center) == "系统确认")
        precondition(RemoteButtonPresentation.actionDetail(for: .system, button: .volumeUp) == "系统音量")
        precondition(RemoteButtonPresentation.actionDetail(for: .none, button: .menu) == "禁用此按键")
        print("RemoteButtonGuideSpecCheck passed")
    }
}
