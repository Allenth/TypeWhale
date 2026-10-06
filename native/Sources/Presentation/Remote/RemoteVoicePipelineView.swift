import AppKit

@MainActor
final class RemoteVoicePipelineView: NSView {
    private let bluetoothStage = label("未连接", size: 10, weight: .medium)
    private let controlStage = label("等待", size: 10, weight: .medium)
    private let packetStage = label("0 包", size: 10, weight: .medium)
    private let pcmStage = label("等待", size: 10, weight: .medium)
    private let sessionStage = label("空闲", size: 10, weight: .medium)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        [bluetoothStage, controlStage, packetStage, pcmStage, sessionStage].forEach {
            $0.alignment = .center
            $0.textColor = UITheme.waterInkMuted
        }
        let group = RemoteInspectorSectionFactory.group(title: "语音链路", body: makePipeline())
        RemoteInspectorSectionFactory.pin(group, to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: RemoteInputSnapshot) {
        bluetoothStage.stringValue = RemoteInspectorPresentation.bluetoothStageText(snapshot.phase)
        controlStage.stringValue = snapshot.pipeline.controlReady ? "已就绪" : "等待"
        packetStage.stringValue = "\(snapshot.pipeline.audioPacketCount) 包"
        pcmStage.stringValue = snapshot.pipeline.audioPacketCount > 0
            ? String(format: "%.0f dB", snapshot.pipeline.pcmLevelDB)
            : "等待"
        sessionStage.stringValue = snapshot.pipeline.typeWhaleSessionActive
            ? "录音中"
            : (snapshot.phase == .processing ? "处理中" : "空闲")
    }

    private func makePipeline() -> NSView {
        let stages = [
            stage(name: "蓝牙", value: bluetoothStage),
            stage(name: "控制通道", value: controlStage),
            stage(name: "音频包", value: packetStage),
            stage(name: "PCM", value: pcmStage),
            stage(name: "TypeWhale", value: sessionStage),
        ]
        let row = NSStackView(views: stages)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 6
        let help = label("按住语音键开始，松开后结束并写入当前输入位置。", size: 10)
        help.textColor = UITheme.waterInkFaint
        let stack = RemoteInspectorSectionFactory.vertical([row, help], spacing: 9)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func stage(name: String, value: NSTextField) -> NSView {
        let title = label(name, size: 9, weight: .medium)
        title.alignment = .center
        title.textColor = UITheme.waterInkFaint
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = UITheme.waterInkLine.cgColor
        dot.layer?.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let dotRow = NSStackView(views: [flexSpacer(), dot, flexSpacer()])
        dotRow.orientation = .horizontal
        return RemoteInspectorSectionFactory.vertical([title, dotRow, value], spacing: 3)
    }
}
