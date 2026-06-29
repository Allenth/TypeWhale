import AppKit

private enum RecentTranscriptionStorageKey {
    static let records = "recentTranscriptionRecords"
    static let legacyTexts = "recentTranscriptions"
}

extension MainViewController {
    func addRecentTranscription(
        _ text: String,
        recognitionSeconds: Double,
        sourceText: String? = nil,
        translatedText: String? = nil,
        translationDirection: SmartTranslationDirection? = nil,
        usage: SmartUsage? = nil
    ) {
        guard !text.isEmpty else { return }
        let record = RecentTranscription(
            text: text,
            recognitionSeconds: recognitionSeconds,
            sourceText: sourceText,
            translatedText: translatedText,
            translationDirection: translationDirection,
            usage: usage
        )
        recentRecords.insert(record, at: 0)
        recentRecords = limitedRecentRecords(recentRecords)
        saveRecentTranscriptions()
        rebuildRecentRows()
    }

    func loadRecentTranscriptions() -> [RecentTranscription] {
        if let data = UserDefaults.standard.data(forKey: RecentTranscriptionStorageKey.records),
           let records = try? JSONDecoder().decode([RecentTranscription].self, from: data) {
            return limitedRecentRecords(records)
        }
        let legacy = UserDefaults.standard.stringArray(forKey: RecentTranscriptionStorageKey.legacyTexts) ?? []
        return Array(legacy.prefix(maxRecentTranscriptions)).map { RecentTranscription(text: $0, recognitionSeconds: nil) }
    }

    func saveRecentTranscriptions() {
        recentRecords = limitedRecentRecords(recentRecords)
        if let data = try? JSONEncoder().encode(recentRecords) {
            UserDefaults.standard.set(data, forKey: RecentTranscriptionStorageKey.records)
        }
        UserDefaults.standard.set(recentRecords.map(\.text), forKey: RecentTranscriptionStorageKey.legacyTexts)
    }

    func rebuildRecentRows() {
        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if recentRecords.isEmpty {
            let empty = label("尚无转录结果", size: 13)
            empty.textColor = .secondaryLabelColor
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            empty.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
                empty.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                empty.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            ])
            recentStack.addArrangedSubview(wrapper)
            return
        }
        for (index, record) in recentRecords.enumerated() {
            let metaLabel = label(record.timeText, size: 9, weight: .medium)
            metaLabel.textColor = .secondaryLabelColor
            metaLabel.maximumNumberOfLines = 1
            metaLabel.lineBreakMode = .byTruncatingTail
            metaLabel.translatesAutoresizingMaskIntoConstraints = false
            let usageLabel = label(record.usage?.compactText ?? "", size: 9, weight: .medium)
            usageLabel.textColor = UITheme.sectionTitle
            usageLabel.alignment = .right
            usageLabel.maximumNumberOfLines = 1
            usageLabel.lineBreakMode = .byTruncatingTail
            usageLabel.translatesAutoresizingMaskIntoConstraints = false
            usageLabel.isHidden = record.usage == nil
            usageLabel.toolTip = record.usage?.detailText

            let textLabel = label(displayText(for: record), size: 11)
            textLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.86)
            textLabel.maximumNumberOfLines = record.hasTranslation ? 5 : 3
            textLabel.lineBreakMode = .byWordWrapping
            (textLabel.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
            textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textLabel.translatesAutoresizingMaskIntoConstraints = false

            let copyButton = NSButton()
            copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
            copyButton.bezelStyle = .inline
            copyButton.isBordered = false
            copyButton.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.42)
            copyButton.toolTip = "复制"
            copyButton.tag = index
            copyButton.target = self
            copyButton.action = #selector(copyRecent(_:))
            copyButton.translatesAutoresizingMaskIntoConstraints = false

            let row = RecentTranscriptionRowView(index: index) { [weak self] index in
                self?.copyRecent(at: index)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(metaLabel)
            row.addSubview(usageLabel)
            row.addSubview(textLabel)
            row.addSubview(copyButton)
            recentStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: recentStack.widthAnchor),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: record.hasTranslation ? 78 : 58),
                metaLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                metaLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
                metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: usageLabel.leadingAnchor, constant: -8),
                usageLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                usageLabel.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
                usageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 112),
                textLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                textLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
                textLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
                textLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
                copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                copyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                copyButton.widthAnchor.constraint(equalToConstant: 24),
                copyButton.heightAnchor.constraint(equalToConstant: 24),
            ])
            if index < recentRecords.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                    divider.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                    divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                ])
            }
        }
    }

    @objc func copyRecent(_ sender: NSButton) {
        copyRecent(at: sender.tag)
    }

    func copyRecent(at index: Int) {
        guard recentRecords.indices.contains(index) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayText(for: recentRecords[index]), forType: .string)
        setPrimaryStatus("已复制最近转录", detail: "最近转录内容已复制到剪贴板。", tone: .success)
        ToastPresenter.shared.show("已复制到剪贴板", style: .success)
    }

    func displayText(for record: RecentTranscription) -> String {
        guard record.hasTranslation,
              let sourceText = record.sourceText,
              let translatedText = record.translatedText,
              let direction = record.translationDirection else {
            return record.text
        }
        return "\(direction.sourceLabel)：\(sourceText)\n\(direction.targetLabel)：\(translatedText)"
    }

    private func limitedRecentRecords(_ records: [RecentTranscription]) -> [RecentTranscription] {
        Array(records.prefix(maxRecentTranscriptions))
    }
}
