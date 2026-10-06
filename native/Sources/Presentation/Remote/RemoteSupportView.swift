import AppKit

@MainActor
final class RemoteSupportView: NSView {
    private let bluetoothPermission = label("检测中", size: 11, weight: .medium)
    private let inputPermission = label("检测中", size: 11, weight: .medium)
    private let settingsButton = NSButton(title: "打开系统设置", target: nil, action: nil)
    private var bluetoothStatus: RemotePermissionStatus = .unknown

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        settingsButton.target = self
        settingsButton.action = #selector(openSystemSettings(_:))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.setAccessibilityLabel("打开隐私与安全系统设置")

        let groups = RemoteInspectorSectionFactory.vertical([
            RemoteInspectorSectionFactory.group(title: "权限与隐私", body: makePermissions()),
            RemoteInspectorSectionFactory.group(title: "使用与排障", body: makeHelp()),
        ], spacing: UILayout.groupSpacing)
        RemoteInspectorSectionFactory.pin(groups, to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: RemoteInputSnapshot) {
        bluetoothStatus = snapshot.bluetoothPermission
        bluetoothPermission.stringValue = RemoteInspectorPresentation.permissionText(snapshot.bluetoothPermission)
        inputPermission.stringValue = RemoteInspectorPresentation.permissionText(snapshot.inputMonitoringPermission)
    }

    private func makePermissions() -> NSView {
        let bluetoothRow = permissionRow(name: "蓝牙", value: bluetoothPermission)
        let inputRow = permissionRow(name: "输入监控", value: inputPermission)
        let actionRow = NSStackView(views: [inputRow, flexSpacer(), settingsButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        let privacy = label("不保存原始语音，不记录蓝牙地址；识别隐私取决于你选择的 TypeWhale 模型。", size: 10)
        privacy.textColor = UITheme.waterInkFaint
        let stack = RemoteInspectorSectionFactory.vertical([bluetoothRow, actionRow, privacy], spacing: 7)
        bluetoothRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeHelp() -> NSView {
        let lines = [
            instruction(number: "1", text: "Home + Menu 进入配对，点击“开始扫描”"),
            instruction(number: "2", text: "显示“可以说话”后，按住语音键讲话"),
            instruction(number: "3", text: "松开语音键，TypeWhale 完成识别和写入"),
        ]
        let recovery = label("断连：等待自动重试或点击重试。无声：查看上方语音链路停在哪一步。按键无效：检查输入监控。", size: 10)
        recovery.textColor = UITheme.waterInkMuted
        return RemoteInspectorSectionFactory.vertical(lines + [hairlineView(), recovery], spacing: 7)
    }

    private func permissionRow(name: String, value: NSTextField) -> NSView {
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = UITheme.waterInkWarning.cgColor
        dot.layer?.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let row = NSStackView(views: [dot, controlRowLabel(name, compact: true), dottedLeaderView(), value])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func instruction(number: String, text: String) -> NSView {
        let badge = label(number, size: 10, weight: .bold)
        badge.alignment = .center
        badge.textColor = UITheme.waterInkText
        let keycap = KeycapView(badge, minWidth: 22, height: 22)
        let row = NSStackView(views: [keycap, label(text, size: 11)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func openSystemSettings(_ sender: NSButton) {
        let pane = bluetoothStatus == .denied
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}
