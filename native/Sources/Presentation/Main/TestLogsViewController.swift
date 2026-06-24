import AppKit

@MainActor
final class TestLogsViewController: NSViewController {
    private enum LogSection: Int {
        case launch
        case crash
        case environment

        var title: String {
            switch self {
            case .launch: return "启动"
            case .crash: return "崩溃"
            case .environment: return "环境"
            }
        }
    }

    private let pathLabel = label("", size: 11)
    private let textView = NSTextView()
    private let segmented = NSSegmentedControl(labels: [
        LogSection.launch.title,
        LogSection.crash.title,
        LogSection.environment.title,
    ], trackingMode: .selectOne, target: nil, action: nil)
    private var currentSection: LogSection = .launch
    private var currentText = ""

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = label("测试日志", size: 14, weight: .semibold)
        let refreshButton = toolbarButton("刷新", imageName: "arrow.clockwise", action: #selector(refresh))
        let copyButton = toolbarButton("复制", imageName: "doc.on.doc", action: #selector(copyCurrentLog))
        let openButton = toolbarButton("打开目录", imageName: "folder", action: #selector(openLogsFolder))
        let buttonRow = NSStackView(views: [refreshButton, copyButton, openButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let header = NSStackView(views: [title, flexSpacer(), buttonRow])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        segmented.selectedSegment = LogSection.launch.rawValue
        segmented.target = self
        segmented.action = #selector(changeSection)

        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 1
        pathLabel.lineBreakMode = .byTruncatingMiddle

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.72)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView(views: [header, segmented, pathLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            segmented.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 312),
        ])

        view = root
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }
        switch currentSection {
        case .launch:
            currentText = launchLogText()
            pathLabel.stringValue = LaunchDiagnostics.logFileURL.path
        case .crash:
            let reports = crashReportSummaries()
            currentText = reports.text
            pathLabel.stringValue = reports.path
        case .environment:
            currentText = environmentText()
            pathLabel.stringValue = Bundle.main.bundlePath
        }
        textView.string = currentText
        textView.scrollToBeginningOfDocument(nil)
    }

    @objc private func changeSection() {
        currentSection = LogSection(rawValue: segmented.selectedSegment) ?? .launch
        reload()
    }

    @objc private func refresh() {
        reload()
    }

    @objc private func copyCurrentLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentText, forType: .string)
    }

    @objc private func openLogsFolder() {
        let directory = LaunchDiagnostics.logFileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(directory)
    }

    private func toolbarButton(_ title: String, imageName: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        return button
    }

    private func launchLogText() -> String {
        do {
            let text = try String(contentsOf: LaunchDiagnostics.logFileURL, encoding: .utf8)
            return tail(text, maxCharacters: 24_000)
        } catch {
            return "未找到启动日志\n\(LaunchDiagnostics.logFileURL.path)\n\n打开或测试一次 App 后这里会出现启动、ASR、权限等诊断记录。"
        }
    }

    private func crashReportSummaries() -> (text: String, path: String) {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DiagnosticReports", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let reports = files
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasPrefix("typewhale") && (name.hasSuffix(".ips") || name.hasSuffix(".crash"))
            }
            .sorted { lhs, rhs in
                modificationDate(lhs) > modificationDate(rhs)
            }
            .prefix(5)

        guard !reports.isEmpty else {
            return (
                "未找到 TypeWhale 崩溃报告\n\(directory.path)",
                directory.path
            )
        }

        let text = reports.map { report in
            crashSummary(for: report)
        }.joined(separator: "\n\n" + String(repeating: "-", count: 72) + "\n\n")
        return (text, directory.path)
    }

    private func crashSummary(for url: URL) -> String {
        let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .ascii))
            ?? ""
        let interestingPrefixes = [
            "Process:",
            "Identifier:",
            "Version:",
            "Code Type:",
            "OS Version:",
            "Exception Type:",
            "Exception Codes:",
            "Termination Reason:",
            "Crashed Thread:",
            "Dyld Error Message:",
            "Application Specific Information:",
        ]
        let summary = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                interestingPrefixes.contains { line.hasPrefix($0) }
                    || line.contains("Symbol not found")
                    || line.contains("Library not loaded")
                    || line.contains("Reason:")
                    || line.contains("dlopen")
            }
            .prefix(80)
            .joined(separator: "\n")
        let body = summary.isEmpty ? tail(raw, maxCharacters: 6_000) : summary
        return "\(url.lastPathComponent)\n修改时间：\(format(modificationDate(url)))\n\n\(body)"
    }

    private func environmentText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "--"
        let build = info["CFBundleVersion"] as? String ?? "--"
        let minimum = info["LSMinimumSystemVersion"] as? String ?? "--"
        let process = ProcessInfo.processInfo
        let asrDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("NativeASR", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
        let modelDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)

        var lines: [String] = [
            "App：TypeWhale \(version) (\(build))",
            "最低系统：macOS \(minimum)",
            "当前系统：\(process.operatingSystemVersionString)",
            "Bundle：\(Bundle.main.bundlePath)",
            "日志：\(LaunchDiagnostics.logFileURL.path)",
            "",
            "ASR 运行库：",
        ]

        [
            "libsherpa-onnx-c-api.dylib",
            "libonnxruntime.1.24.4.dylib",
            "libc++.1.dylib",
        ].forEach { name in
            lines.append(fileStatus(name, in: asrDirectory))
        }

        lines.append("")
        lines.append("模型：")
        [
            "sensevoice-native/model.onnx",
            "sensevoice-native/tokens.txt",
            "vad/silero_vad.onnx",
        ].forEach { name in
            lines.append(fileStatus(name, in: modelDirectory))
        }
        return lines.joined(separator: "\n")
    }

    private func fileStatus(_ relativePath: String, in directory: URL?) -> String {
        guard let url = directory?.appendingPathComponent(relativePath) else {
            return "✗ \(relativePath) · 路径不可用"
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              FileManager.default.fileExists(atPath: url.path) else {
            return "✗ \(relativePath) · 缺失"
        }
        let size = values.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "--"
        return "✓ \(relativePath) · \(size)"
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func tail(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return "…\n" + String(text.suffix(maxCharacters))
    }
}
