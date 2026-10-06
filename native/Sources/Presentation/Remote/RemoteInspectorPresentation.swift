import AppKit

struct RemotePhasePresentation {
    let title: String
    let detail: String
    let action: String
    let accessibilityAction: String
    let actionEnabled: Bool
    let color: NSColor
}

enum RemoteInspectorPresentation {
    @MainActor
    static func phase(_ phase: RemoteConnectionPhase) -> RemotePhasePresentation {
        switch phase {
        case .disabled:
            return RemotePhasePresentation(
                title: "遥控器输入已关闭",
                detail: "启用后可连接小米蓝牙遥控器 2 Pro",
                action: "启用",
                accessibilityAction: "启用遥控器输入",
                actionEnabled: true,
                color: UITheme.waterInkFaint
            )
        case .bluetoothUnavailable:
            return RemotePhasePresentation(
                title: "蓝牙不可用",
                detail: "请开启蓝牙并检查 TypeWhale 的蓝牙权限",
                action: "等待蓝牙",
                accessibilityAction: "蓝牙当前不可用",
                actionEnabled: false,
                color: UITheme.waterInkWarning
            )
        case .unpaired:
            return RemotePhasePresentation(
                title: "未发现遥控器",
                detail: "按住 Home + Menu 进入配对模式",
                action: "开始扫描",
                accessibilityAction: "开始扫描小米遥控器",
                actionEnabled: true,
                color: UITheme.waterInkWarning
            )
        case .scanning:
            return RemotePhasePresentation(
                title: "正在扫描",
                detail: "正在查找支持语音的小米遥控器",
                action: "停止扫描",
                accessibilityAction: "停止扫描小米遥控器",
                actionEnabled: true,
                color: UITheme.waterInkMistBlue
            )
        case .connecting:
            return RemotePhasePresentation(
                title: "正在连接",
                detail: "已发现设备，正在建立蓝牙连接",
                action: "连接中",
                accessibilityAction: "正在连接小米遥控器",
                actionEnabled: false,
                color: UITheme.waterInkMistBlue
            )
        case .negotiating:
            return RemotePhasePresentation(
                title: "正在准备语音",
                detail: "正在协商控制通道和音频格式",
                action: "准备中",
                accessibilityAction: "正在准备遥控器语音",
                actionEnabled: false,
                color: UITheme.waterInkMistBlue
            )
        case .ready:
            return RemotePhasePresentation(
                title: "可以说话",
                detail: "按住遥控器语音键开始输入",
                action: "重新扫描",
                accessibilityAction: "重新扫描小米遥控器",
                actionEnabled: true,
                color: UITheme.waterInkSuccess
            )
        case .listening:
            return RemotePhasePresentation(
                title: "正在听",
                detail: "松开语音键后 TypeWhale 开始收尾",
                action: "录音中",
                accessibilityAction: "遥控器正在录音",
                actionEnabled: false,
                color: UITheme.waterInkRecording
            )
        case .processing:
            return RemotePhasePresentation(
                title: "正在处理",
                detail: "TypeWhale 正在识别并写入文字",
                action: "处理中",
                accessibilityAction: "TypeWhale 正在处理遥控器语音",
                actionEnabled: false,
                color: UITheme.waterInkMistBlue
            )
        case .retrying(let attempt):
            return RemotePhasePresentation(
                title: "连接已断开",
                detail: "正在进行第 \(attempt) 次自动重试",
                action: "立即重试",
                accessibilityAction: "立即重试连接小米遥控器",
                actionEnabled: true,
                color: UITheme.waterInkWarning
            )
        case .busy:
            return RemotePhasePresentation(
                title: "TypeWhale 正忙",
                detail: "请等待当前语音任务完成后再按遥控器",
                action: "等待",
                accessibilityAction: "TypeWhale 当前正忙",
                actionEnabled: false,
                color: UITheme.waterInkWarning
            )
        case .protocolFailure(let reason):
            return RemotePhasePresentation(
                title: "遥控器语音不可用",
                detail: reason,
                action: "重试",
                accessibilityAction: "重试遥控器语音连接",
                actionEnabled: true,
                color: .systemRed
            )
        }
    }

    static func bluetoothStageText(_ phase: RemoteConnectionPhase) -> String {
        switch phase {
        case .connecting: return "连接中"
        case .negotiating, .ready, .listening, .processing, .busy: return "已连接"
        case .retrying: return "重试中"
        default: return "未连接"
        }
    }

    static func permissionText(_ value: RemotePermissionStatus) -> String {
        switch value {
        case .unknown: return "等待系统授权"
        case .allowed: return "已允许"
        case .denied: return "未允许"
        case .restricted: return "受系统限制"
        }
    }
}
