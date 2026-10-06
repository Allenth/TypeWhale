import AppKit

@MainActor
final class RemoteConnectionOverviewView: NSView {
    var onEnabledChange: ((Bool) -> Void)?
    var onPrimaryAction: (() -> Void)?

    private let statusDot = NSView()
    private let statusTitle = label("遥控器输入已关闭", size: 15, weight: .semibold)
    private let statusDetail = label("启用后可连接小米蓝牙遥控器 2 Pro", size: 11)
    private let enabledSwitch = NSButton(checkboxWithTitle: "遥控器输入", target: nil, action: nil)
    private let primaryButton = NSButton(title: "开始扫描", target: nil, action: nil)
    private let deviceName = label("尚未发现小米遥控器", size: 13, weight: .semibold)
    private let deviceModel = label("型号 —", size: 10)
    private let deviceBattery = label("电量 —", size: 10)
    private let deviceSignal = label("信号 —", size: 10)
    private let pairingHelp = label("同时按住遥控器的 Home + Menu，看到指示灯闪烁后点击扫描。", size: 11)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        configureControls()
        let groups = RemoteInspectorSectionFactory.vertical([
            RemoteInspectorSectionFactory.group(
                title: "遥控器输入",
                body: makeHero(),
                prominence: .lead
            ),
            RemoteInspectorSectionFactory.group(title: "设备", body: makeDevice()),
        ], spacing: UILayout.groupSpacing)
        RemoteInspectorSectionFactory.pin(groups, to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: RemoteInputSnapshot) {
        enabledSwitch.state = snapshot.enabled ? .on : .off
        let presentation = RemoteInspectorPresentation.phase(snapshot.phase)
        statusTitle.stringValue = presentation.title
        statusTitle.setAccessibilityLabel("遥控器状态：\(presentation.title)")
        statusDetail.stringValue = presentation.detail
        primaryButton.title = presentation.action
        primaryButton.isEnabled = presentation.actionEnabled
        primaryButton.setAccessibilityLabel(presentation.accessibilityAction)
        statusDot.layer?.backgroundColor = presentation.color.cgColor

        deviceName.stringValue = snapshot.device.name ?? "尚未发现小米遥控器"
        deviceModel.stringValue = "型号 \(snapshot.device.model ?? "—")"
        deviceBattery.stringValue = snapshot.device.batteryPercent.map { "电量 \($0)%" } ?? "电量 —"
        deviceSignal.stringValue = snapshot.device.signalStrength.map { "信号 \($0) dBm" } ?? "信号 —"
        pairingHelp.isHidden = snapshot.device.name != nil
    }

    private func configureControls() {
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        statusDetail.textColor = UITheme.waterInkMuted
        pairingHelp.textColor = UITheme.waterInkMuted
        [deviceModel, deviceBattery, deviceSignal].forEach { $0.textColor = UITheme.waterInkFaint }

        enabledSwitch.setButtonType(.switch)
        enabledSwitch.target = self
        enabledSwitch.action = #selector(toggleEnabled(_:))
        enabledSwitch.setAccessibilityLabel("启用遥控器输入")

        primaryButton.target = self
        primaryButton.action = #selector(runPrimaryAction(_:))
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .small
        primaryButton.setAccessibilityLabel("开始扫描小米遥控器")
    }

    private func makeHero() -> NSView {
        let titleRow = NSStackView(views: [statusDot, statusTitle, flexSpacer(), primaryButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let localCaption = label("语音直接进入 TypeWhale，不使用虚拟麦克风。", size: 10)
        localCaption.textColor = UITheme.waterInkFaint
        let enableRow = NSStackView(views: [enabledSwitch, flexSpacer(), localCaption])
        enableRow.orientation = .horizontal
        enableRow.alignment = .centerY
        enableRow.spacing = 10

        let stack = RemoteInspectorSectionFactory.vertical(
            [titleRow, statusDetail, hairlineView(), enableRow],
            spacing: 8
        )
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        enableRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeDevice() -> NSView {
        let metadata = NSStackView(views: [deviceModel, deviceBattery, deviceSignal])
        metadata.orientation = .horizontal
        metadata.distribution = .fillEqually
        metadata.spacing = 10
        let autoConnect = label("TypeWhale 会自动连接已配对且支持语音的设备。", size: 10)
        autoConnect.textColor = UITheme.waterInkFaint
        let stack = RemoteInspectorSectionFactory.vertical(
            [deviceName, metadata, hairlineView(), pairingHelp, autoConnect],
            spacing: 7
        )
        metadata.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        onEnabledChange?(sender.state == .on)
    }

    @objc private func runPrimaryAction(_ sender: NSButton) {
        onPrimaryAction?()
    }
}
