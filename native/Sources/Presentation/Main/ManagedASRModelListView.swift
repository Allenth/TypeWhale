import AppKit

final class ManagedASRModelListView: NSView {
    private let downloader: ManagedASRModelDownloader
    private let rootDirectory: URL
    private let onMessage: (String) -> Void
    private var rows: [ManagedASRModelRowView] = []

    init(
        downloader: ManagedASRModelDownloader,
        rootDirectory: URL = ManagedASRModelCatalog.rootDirectory(in: AppPaths.models),
        onMessage: @escaping (String) -> Void
    ) {
        self.downloader = downloader
        self.rootDirectory = rootDirectory
        self.onMessage = onMessage
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        downloader.onStateChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        rows = ManagedASRModelCatalog.models.map { model in
            let row = ManagedASRModelRowView(model: model, destination: downloader.destinationDirectory(for: model))
            row.onDownload = { [weak self] model in
                self?.onMessage("开始下载 \(model.displayName)")
                self?.downloader.download(model)
            }
            row.onCancel = { [weak self] model in
                self?.onMessage("已停止下载 \(model.displayName)")
                self?.downloader.cancelDownload(model)
            }
            return row
        }

        let list = modelListCard(rows)
        let stack = NSStackView(views: [list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func modelListCard(_ modelRows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let targetHeader = targetDirectoryHeader()
        stack.addArrangedSubview(targetHeader)
        targetHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let headerSeparator = hairlineView()
        stack.addArrangedSubview(headerSeparator)
        headerSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for (index, row) in modelRows.enumerated() {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if index < modelRows.count - 1 {
                let separator = hairlineView()
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        return roundedBox(stack, hPad: 0, vPad: 0)
    }

    private func targetDirectoryHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let targetCaption = label("目标目录", size: 10, weight: .medium)
        targetCaption.textColor = UITheme.sectionTitle
        targetCaption.setContentHuggingPriority(.required, for: .horizontal)
        targetCaption.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pathLabel = label(rootDirectory.path, size: 10, weight: .medium)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.toolTip = rootDirectory.path
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let openButton = NSButton(title: "打开", target: self, action: #selector(openRootDirectory))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.font = .systemFont(ofSize: 11, weight: .medium)
        openButton.setContentHuggingPriority(.required, for: .horizontal)
        openButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let llmCaption = label("大模型", size: 10, weight: .medium)
        llmCaption.textColor = UITheme.sectionTitle
        llmCaption.setContentHuggingPriority(.required, for: .horizontal)
        llmCaption.setContentCompressionResistancePriority(.required, for: .horizontal)

        let llmHint = label("Ollama 本地整理模型", size: 10, weight: .medium)
        llmHint.textColor = .secondaryLabelColor
        llmHint.lineBreakMode = .byTruncatingTail
        llmHint.maximumNumberOfLines = 1
        llmHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let qwen8Button = linkButton(
            title: "8B",
            action: #selector(openQwen8BDownloadLink),
            toolTip: "打开 Ollama Qwen3 8B 下载页：ollama run qwen3:8b"
        )
        let qwen35Button = linkButton(
            title: "35B",
            action: #selector(openQwen35BDownloadLink),
            toolTip: "打开 Ollama Qwen3.6 35B 下载页：ollama run qwen3.6:35b-mlx"
        )

        [targetCaption, pathLabel, openButton, llmCaption, llmHint, qwen8Button, qwen35Button].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 68),
            targetCaption.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            targetCaption.topAnchor.constraint(equalTo: header.topAnchor, constant: 11),
            targetCaption.widthAnchor.constraint(equalToConstant: 52),
            openButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            openButton.centerYAnchor.constraint(equalTo: targetCaption.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 54),
            pathLabel.leadingAnchor.constraint(equalTo: targetCaption.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10),
            pathLabel.centerYAnchor.constraint(equalTo: targetCaption.centerYAnchor),

            llmCaption.leadingAnchor.constraint(equalTo: targetCaption.leadingAnchor),
            llmCaption.topAnchor.constraint(equalTo: targetCaption.bottomAnchor, constant: 11),
            llmCaption.widthAnchor.constraint(equalTo: targetCaption.widthAnchor),
            qwen35Button.trailingAnchor.constraint(equalTo: openButton.trailingAnchor),
            qwen35Button.centerYAnchor.constraint(equalTo: llmCaption.centerYAnchor),
            qwen35Button.widthAnchor.constraint(equalToConstant: 54),
            qwen8Button.trailingAnchor.constraint(equalTo: qwen35Button.leadingAnchor, constant: -6),
            qwen8Button.centerYAnchor.constraint(equalTo: llmCaption.centerYAnchor),
            qwen8Button.widthAnchor.constraint(equalToConstant: 44),
            llmHint.leadingAnchor.constraint(equalTo: llmCaption.trailingAnchor, constant: 8),
            llmHint.trailingAnchor.constraint(equalTo: qwen8Button.leadingAnchor, constant: -10),
            llmHint.centerYAnchor.constraint(equalTo: llmCaption.centerYAnchor),
        ])

        return header
    }

    private func linkButton(title: String, action: Selector, toolTip: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.toolTip = toolTip
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func refresh() {
        for row in rows {
            let state = downloader.state(for: row.model)
            row.update(state: state, destination: downloader.destinationDirectory(for: row.model))
        }
    }

    @objc private func openRootDirectory() {
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(rootDirectory)
    }

    @objc private func openQwen8BDownloadLink() {
        openDownloadLink(
            URL(string: "https://ollama.com/library/qwen3%3A8b"),
            message: "打开 Qwen3 8B 下载链接"
        )
    }

    @objc private func openQwen35BDownloadLink() {
        openDownloadLink(
            URL(string: "https://ollama.com/library/qwen3.6%3A35b-mlx"),
            message: "打开 Qwen3.6 35B 下载链接"
        )
    }

    private func openDownloadLink(_ url: URL?, message: String) {
        guard let url else { return }
        onMessage(message)
        NSWorkspace.shared.open(url)
    }
}

private final class ManagedASRModelRowView: NSView {
    let model: ManagedASRModel
    var onDownload: ((ManagedASRModel) -> Void)?
    var onCancel: ((ManagedASRModel) -> Void)?

    private let dot = NSView()
    private let nameLabel: NSTextField
    private let capabilityLabel: NSTextField
    private let detailLabel: NSTextField
    private let statusLabel: NSTextField
    private let pathLabel: NSTextField
    private let progressRing = CircularProgressView()
    private let downloadButton = NSButton(title: "下载", target: nil, action: nil)
    private var isDownloading = false

    init(model: ManagedASRModel, destination: URL) {
        self.model = model
        nameLabel = label(model.displayName, size: 12, weight: .semibold)
        capabilityLabel = label("\(model.capabilityText) · \(model.sizeText)", size: 10, weight: .medium)
        detailLabel = label(model.detailText, size: 10)
        statusLabel = label("检查中", size: 10, weight: .medium)
        pathLabel = label(destination.lastPathComponent, size: 10)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(destination: destination)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(destination: URL) {
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3

        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        capabilityLabel.textColor = UITheme.sectionTitle
        capabilityLabel.maximumNumberOfLines = 1
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 1
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.toolTip = destination.path
        progressRing.isHidden = true

        downloadButton.target = self
        downloadButton.action = #selector(download)
        downloadButton.bezelStyle = .rounded
        downloadButton.controlSize = .small
        downloadButton.font = .systemFont(ofSize: 11, weight: .medium)
        downloadButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        downloadButton.setContentHuggingPriority(.required, for: .horizontal)
        downloadButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [nameLabel, flexSpacer(), progressRing, downloadButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 7

        let pathIcon = symbolIcon("folder", size: 10, color: NSColor(calibratedWhite: 1, alpha: 0.35))
        pathIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let pathRow = NSStackView(views: [pathIcon, pathLabel])
        pathRow.orientation = .horizontal
        pathRow.alignment = .centerY
        pathRow.spacing = 3

        let statusRow = NSStackView(views: [statusLabel, flexSpacer(), pathRow])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let textStack = NSStackView(views: [titleRow, capabilityLabel, detailLabel, statusRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(dot)
        row.addSubview(textStack)
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 86),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dot.topAnchor.constraint(equalTo: textStack.topAnchor, constant: 7),
            textStack.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 9),
            textStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            titleRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
    }

    func update(state: ManagedASRModelDownloader.State, destination: URL) {
        pathLabel.stringValue = destination.lastPathComponent
        pathLabel.toolTip = destination.path
        switch state {
        case .missing:
            isDownloading = false
            dot.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.28).cgColor
            progressRing.isHidden = true
            statusLabel.stringValue = "未下载"
            statusLabel.textColor = .secondaryLabelColor
            downloadButton.title = "下载"
            downloadButton.isEnabled = true
            downloadButton.toolTip = destination.path
        case .ready:
            isDownloading = false
            dot.layer?.backgroundColor = UITheme.brandGreen.cgColor
            progressRing.isHidden = true
            statusLabel.stringValue = "已下载"
            statusLabel.textColor = UITheme.brandGreen
            downloadButton.title = "已下载"
            downloadButton.isEnabled = false
            downloadButton.toolTip = destination.path
        case .downloading(let progress, let downloadedBytes):
            isDownloading = true
            dot.layer?.backgroundColor = UITheme.brandYellow.cgColor
            progressRing.progress = progress
            progressRing.isHidden = false
            statusLabel.stringValue = "下载中 \(Int(progress * 100))% · \(Self.formatBytes(downloadedBytes))"
            statusLabel.textColor = .secondaryLabelColor
            downloadButton.title = "停止"
            downloadButton.isEnabled = true
            downloadButton.toolTip = "停止下载并清理临时文件"
        case .failed(let message):
            isDownloading = false
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            progressRing.isHidden = true
            statusLabel.stringValue = "失败"
            statusLabel.textColor = .systemRed
            downloadButton.title = "重试"
            downloadButton.isEnabled = true
            downloadButton.toolTip = message
        }
    }

    @objc private func download() {
        if isDownloading {
            onCancel?(model)
        } else {
            onDownload?(model)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

private final class CircularProgressView: NSView {
    var progress: Double = 0 {
        didSet {
            progress = min(1, max(0, progress))
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.4
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        track.stroke()

        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(progress) * 360,
            clockwise: true
        )
        ring.lineWidth = 2.4
        UITheme.brandYellow.setStroke()
        ring.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.82),
            .paragraphStyle: paragraph,
        ]
        let textRect = bounds.insetBy(dx: 2, dy: (bounds.height - 8) / 2)
        "\(Int(progress * 100))".draw(in: textRect, withAttributes: attributes)
    }
}
