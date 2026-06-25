import AppKit

extension MainViewController {
    // MARK: - Preferences window (⌘,)

    /// 偏好窗口内容懒构建一次：把快捷键 / 智能整理 / 翻译 / 截图 / 系统的配置控件装进标签页。
    func makePreferencesViewController() -> NSViewController {
        if let cached = preferencesViewController { return cached }
        let controller = NSViewController()
        controller.view = buildPreferencesContentView()
        controller.title = "偏好设置"
        preferencesViewController = controller
        return controller
    }

    func buildPreferencesContentView() -> NSView {
        [hotkeyValue, secondaryHotkeyValue, screenshotHotkeyValue, secondaryScreenshotHotkeyValue, screenshotTranslationHotkeyValue, autoTranslateHotkeyValue, mainWindowHotkeyValue].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
        }
        hotkeyCaptureButton.target = self
        hotkeyCaptureButton.action = #selector(beginHotkeyCapture)
        hotkeyResetButton.target = self
        hotkeyResetButton.action = #selector(resetHotkey)
        secondaryHotkeyCaptureButton.target = self
        secondaryHotkeyCaptureButton.action = #selector(beginSecondaryHotkeyCapture)
        secondaryHotkeyClearButton.target = self
        secondaryHotkeyClearButton.action = #selector(clearSecondaryHotkey)
        screenshotHotkeyCaptureButton.target = self
        screenshotHotkeyCaptureButton.action = #selector(beginScreenshotHotkeyCapture)
        screenshotHotkeyResetButton.target = self
        screenshotHotkeyResetButton.action = #selector(resetScreenshotHotkey)
        secondaryScreenshotHotkeyCaptureButton.target = self
        secondaryScreenshotHotkeyCaptureButton.action = #selector(beginSecondaryScreenshotHotkeyCapture)
        secondaryScreenshotHotkeyClearButton.target = self
        secondaryScreenshotHotkeyClearButton.action = #selector(clearSecondaryScreenshotHotkey)
        screenshotTranslationHotkeyCaptureButton.target = self
        screenshotTranslationHotkeyCaptureButton.action = #selector(beginScreenshotTranslationHotkeyCapture)
        screenshotTranslationHotkeyResetButton.target = self
        screenshotTranslationHotkeyResetButton.action = #selector(resetScreenshotTranslationHotkey)
        autoTranslateHotkeyCaptureButton.target = self
        autoTranslateHotkeyCaptureButton.action = #selector(beginAutoTranslateHotkeyCapture)
        autoTranslateHotkeyClearButton.target = self
        autoTranslateHotkeyClearButton.action = #selector(clearAutoTranslateHotkey)
        mainWindowHotkeyCaptureButton.target = self
        mainWindowHotkeyCaptureButton.action = #selector(beginMainWindowHotkeyCapture)
        mainWindowHotkeyResetButton.target = self
        mainWindowHotkeyResetButton.action = #selector(clearMainWindowHotkey)
        let hotkeyButtons = [
            hotkeyCaptureButton,
            hotkeyResetButton,
            secondaryHotkeyCaptureButton,
            secondaryHotkeyClearButton,
            screenshotHotkeyCaptureButton,
            screenshotHotkeyResetButton,
            secondaryScreenshotHotkeyCaptureButton,
            secondaryScreenshotHotkeyClearButton,
            screenshotTranslationHotkeyCaptureButton,
            screenshotTranslationHotkeyResetButton,
            autoTranslateHotkeyCaptureButton,
            autoTranslateHotkeyClearButton,
            mainWindowHotkeyCaptureButton,
            mainWindowHotkeyResetButton,
        ]
        hotkeyButtons.forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
        }
        let captureWidth: CGFloat = 96
        let trailingWidth: CGFloat = 56
        [hotkeyCaptureButton, secondaryHotkeyCaptureButton, screenshotHotkeyCaptureButton, secondaryScreenshotHotkeyCaptureButton, screenshotTranslationHotkeyCaptureButton, autoTranslateHotkeyCaptureButton, mainWindowHotkeyCaptureButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: captureWidth).isActive = true
        }
        [hotkeyResetButton, secondaryHotkeyClearButton, screenshotHotkeyResetButton, secondaryScreenshotHotkeyClearButton, screenshotTranslationHotkeyResetButton, autoTranslateHotkeyClearButton, mainWindowHotkeyResetButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: trailingWidth).isActive = true
        }
        let primaryRow = shortcutRow(title: "主快捷键", captureButton: hotkeyCaptureButton, fallbackButton: hotkeyResetButton)
        let secondaryRow = shortcutRow(title: "备用快捷键", captureButton: secondaryHotkeyCaptureButton, fallbackButton: secondaryHotkeyClearButton)
        let screenshotRow = shortcutRow(title: "截图快捷键", captureButton: screenshotHotkeyCaptureButton, fallbackButton: screenshotHotkeyResetButton)
        let secondaryScreenshotRow = shortcutRow(title: "截图备用", captureButton: secondaryScreenshotHotkeyCaptureButton, fallbackButton: secondaryScreenshotHotkeyClearButton)
        let screenshotTranslationRow = shortcutRow(title: "翻译截图", captureButton: screenshotTranslationHotkeyCaptureButton, fallbackButton: screenshotTranslationHotkeyResetButton)
        let autoTranslateHotkeyRow = shortcutRow(title: "自动翻译", captureButton: autoTranslateHotkeyCaptureButton, fallbackButton: autoTranslateHotkeyClearButton)
        let mainWindowHotkeyRow = shortcutRow(title: "唤起主页", captureButton: mainWindowHotkeyCaptureButton, fallbackButton: mainWindowHotkeyResetButton)

        let smartRewriteControls = NSStackView(views: [autoScopeButton, promptSettingsButton, developerTermsButton, deepSeekKeyButton, deepSeekBalanceButton])
        smartRewriteControls.orientation = .horizontal
        smartRewriteControls.alignment = .centerY
        smartRewriteControls.spacing = 6
        autoScopeButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        promptSettingsButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        developerTermsButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        deepSeekKeyButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        deepSeekBalanceButton.widthAnchor.constraint(equalToConstant: 26).isActive = true

        translationPromptButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        screenshotSaveLocationButton.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(preferencesTab("快捷键", [primaryRow, secondaryRow, screenshotRow, secondaryScreenshotRow, screenshotTranslationRow, autoTranslateHotkeyRow, mainWindowHotkeyRow]))
        tabView.addTabViewItem(preferencesTab(
            "智能整理",
            [stackedOptionRow("范围 · 提示词 · 术语 · Key", smartRewriteControls)],
            caption: "整理「模式」可在主界面右侧快捷设置或桌面胶囊上快速切换。"
        ))
        tabView.addTabViewItem(preferencesTab(
            "翻译",
            [optionRow("翻译提示词", translationPromptButton)],
            caption: "「自动翻译」开关与「翻译方向」可在主界面右侧快捷设置中快速切换。"
        ))
        tabView.addTabViewItem(preferencesTab("截图", [optionRow("截图保存位置", screenshotSaveLocationButton)]))
        tabView.addTabViewItem(preferencesTab("系统", [
            optionRow("胶囊实时预览", realtime),
            optionRow("停顿自动完成", autoFinish),
            optionRow("录音时降低电脑声音", duckSystemAudio),
            optionRow("开机自动启动", launchAtLogin),
        ]))

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        content.appearance = NSAppearance(named: .darkAqua)
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        return content
    }

    func preferencesTab(_ title: String, _ rows: [NSView], caption: String? = nil) -> NSTabViewItem {
        let card = listCard(rows, hPad: UILayout.cardPadH, vPad: UILayout.cardPadV)
        var arranged: [NSView] = [card]
        if let caption {
            let cap = label(caption, size: 11)
            cap.textColor = .secondaryLabelColor
            cap.maximumNumberOfLines = 0
            arranged.append(cap)
        }
        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for arrangedView in arranged {
            arrangedView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
        ])

        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = container
        return item
    }

    @objc func openPreferences() {
        scrollToConfigPanels()
    }

    func section(_ title: String, _ card: NSView) -> NSView {
        let stack = NSStackView(views: [sectionHeader(title), card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILayout.headerSpacing
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func shortcutRow(
        title: String,
        captureButton: NSButton,
        fallbackButton: NSButton
    ) -> NSView {
        let titleLabel = label(title, size: 12)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, flexSpacer(), captureButton, fallbackButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func optionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 12)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: UILayout.rowHeight).isActive = true
        return row
    }

    func compactOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 10, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.72)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, flexSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }

    func stackedOptionRow(_ title: String, _ control: NSView) -> NSView {
        let titleLabel = label(title, size: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true
        row.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return row
    }
}
