import Foundation

enum RemoteButtonPresentation {
    static func title(for button: RemoteButton) -> String {
        switch button {
        case .voice: return "语音键"
        case .dpadUp: return "方向上"
        case .dpadDown: return "方向下"
        case .dpadLeft: return "方向左"
        case .dpadRight: return "方向右"
        case .center: return "确定键"
        case .back: return "返回键"
        case .home: return "主页键"
        case .menu: return "菜单键"
        case .volumeUp: return "音量加"
        case .volumeDown: return "音量减"
        case .tv: return "电视键"
        case .power: return "电源键"
        }
    }

    static func actionTitle(for action: RemoteButtonAction) -> String {
        switch action {
        case .pushToTalk: return "按住说话"
        case .keyboardEscape: return "按 Esc"
        case .keyboardDelete: return "按 Delete"
        case .keyboardReturn: return "按 Return"
        case .lockMac: return "锁定 Mac"
        case .send: return "发送当前内容"
        case .cancel: return "取消当前操作"
        case .toggleMainWindow: return "显示 / 隐藏主窗口"
        case .none: return "禁用此按键"
        case .system: return "保持系统原功能"
        }
    }

    static func actionDetail(for action: RemoteButtonAction, button: RemoteButton) -> String {
        switch action {
        case .pushToTalk:
            return "按住说话"
        case .keyboardEscape:
            return "按 Esc"
        case .keyboardDelete:
            return "按 Delete"
        case .keyboardReturn:
            return "按 Return"
        case .lockMac:
            return "锁定 Mac"
        case .send:
            return "发送当前内容"
        case .cancel:
            return "取消当前操作"
        case .toggleMainWindow:
            return "显示 / 隐藏主窗口"
        case .none:
            return "禁用此按键"
        case .system:
            switch button {
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                return "系统导航"
            case .center:
                return "系统确认"
            case .volumeUp, .volumeDown:
                return "系统音量"
            case .back:
                return "系统返回"
            case .home:
                return "系统主页"
            case .menu:
                return "系统菜单"
            case .tv:
                return "系统电视功能"
            case .power:
                return "系统电源功能"
            case .voice:
                return "系统语音"
            }
        }
    }

    static func editableButtons(supportedButtons: Set<RemoteButton>) -> [RemoteButton] {
        RemoteButton.allCases.filter {
            supportedButtons.contains($0)
        }
    }
}
