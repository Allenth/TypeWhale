import AppKit

final class ThirdPartyNoticesViewController: NSViewController {
    private struct NoticeRow {
        let name: String
        let license: String
        let status: String
        let statusColor: NSColor
        let sourceURL: URL?
        let note: String
    }

    private static let rows = [
        NoticeRow(
            name: "sherpa-onnx",
            license: "Apache-2.0",
            status: "已随包",
            statusColor: .systemGreen,
            sourceURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx"),
            note: "原生语音识别运行库，随包保留 Apache-2.0 notice。"
        ),
        NoticeRow(
            name: "ONNX Runtime",
            license: "MIT",
            status: "已随包",
            statusColor: .systemGreen,
            sourceURL: URL(string: "https://github.com/microsoft/onnxruntime"),
            note: "ONNX 推理运行库，随包保留 MIT notice 和版权说明。"
        ),
        NoticeRow(
            name: "Silero VAD",
            license: "MIT",
            status: "已随包",
            statusColor: .systemGreen,
            sourceURL: URL(string: "https://github.com/snakers4/silero-vad"),
            note: "人声检测模型，随包保留 MIT notice 和版权说明。"
        ),
        NoticeRow(
            name: "SenseVoice / FunASR",
            license: "model-license",
            status: "商业待确认",
            statusColor: .systemYellow,
            sourceURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"),
            note: "随包 ONNX 来源已记录；上游为 FunAudioLLM/SenseVoiceSmall，商业再分发待确认。"
        ),
    ]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 430))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.appearance = NSAppearance(named: .darkAqua)

        let title = label("第三方组件与模型授权", size: 18, weight: .semibold)
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingTail

        let subtitle = label("TypeWhale 随包运行库、模型来源和商业发布检查。", size: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 1
        subtitle.lineBreakMode = .byTruncatingTail

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 5

        let runtimeTitle = sectionTitle("运行库")
        let runtimeRows = Self.rows.prefix(2).map(makeRow)
        let modelTitle = sectionTitle("模型")
        let modelRows = Self.rows.suffix(2).map(makeRow)

        let releaseTitle = sectionTitle("商业发布检查")
        let releaseText = label("SenseVoice/FunASR 当前只作为来源与授权说明随包展示，不写成“可商用”。正式售卖前，需要保存明确商业再分发授权，或替换为授权更清晰的模型。", size: 12)
        releaseText.textColor = .secondaryLabelColor
        releaseText.maximumNumberOfLines = 3
        releaseText.lineBreakMode = .byWordWrapping

        let openNoticesButton = NSButton(title: "打开完整 THIRD_PARTY_NOTICES.md", target: self, action: #selector(openBundledNotices))
        openNoticesButton.bezelStyle = .rounded
        openNoticesButton.controlSize = .regular
        openNoticesButton.setContentHuggingPriority(.required, for: .horizontal)

        let buttonRow = NSStackView(views: [openNoticesButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill

        let separator1 = separator()
        let separator2 = separator()
        let separator3 = separator()
        let stack = NSStackView(views: [
            header,
            separator1,
            runtimeTitle,
        ] + runtimeRows + [
            separator2,
            modelTitle,
        ] + modelRows + [
            separator3,
            releaseTitle,
            releaseText,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44),
            separator1.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44),
            separator2.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44),
            separator3.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44),
            releaseText.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44),
        ])
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let value = label(text, size: 13, weight: .semibold)
        value.maximumNumberOfLines = 1
        return value
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeRow(_ item: NoticeRow) -> NSView {
        let name = label(item.name, size: 13, weight: .medium)
        name.maximumNumberOfLines = 1
        name.lineBreakMode = .byTruncatingTail
        name.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let license = badge(item.license, fill: NSColor.controlAccentColor.withAlphaComponent(0.18), textColor: .labelColor)
        let status = badge(item.status, fill: item.statusColor.withAlphaComponent(0.2), textColor: item.statusColor)

        let sourceButton = NSButton(title: "查看来源", target: self, action: #selector(openSource(_:)))
        sourceButton.bezelStyle = .rounded
        sourceButton.controlSize = .small
        sourceButton.tag = Self.rows.firstIndex { $0.name == item.name } ?? 0
        sourceButton.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [name, license, status, sourceButton, spacer])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.distribution = .fill
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.required, for: .horizontal)

        let note = label(item.note, size: 12)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byWordWrapping

        let row = NSStackView(views: [topRow, note])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 5
        row.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        row.widthAnchor.constraint(equalToConstant: 520).isActive = true
        note.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    private func badge(_ text: String, fill: NSColor, textColor: NSColor) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = .systemFont(ofSize: 11, weight: .medium)
        value.textColor = textColor
        value.alignment = .center
        value.wantsLayer = true
        value.layer?.backgroundColor = fill.cgColor
        value.layer?.cornerRadius = 5
        value.maximumNumberOfLines = 1
        value.lineBreakMode = .byTruncatingTail
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        value.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return value
    }

    @objc private func openSource(_ sender: NSButton) {
        guard Self.rows.indices.contains(sender.tag),
              let url = Self.rows[sender.tag].sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openBundledNotices() {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "未找到第三方组件说明"
        alert.informativeText = "当前 App 包内缺少 THIRD_PARTY_NOTICES.md，请重新构建或安装 TypeWhale。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
