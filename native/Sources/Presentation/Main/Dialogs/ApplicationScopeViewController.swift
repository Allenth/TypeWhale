import AppKit

@MainActor
final class ApplicationScopeViewController: NSViewController {
    private enum SidebarItem: Equatable {
        case category(ApplicationCategory)
        case advancedRules

        var title: String {
            switch self {
            case .category(.recent): return "最近使用"
            case .category(.communication): return "沟通"
            case .category(.productivity): return "办公"
            case .category(.development): return "开发"
            case .category(.browser): return "浏览器"
            case .category(.other): return "其他"
            case .category(.all): return "全部应用"
            case .advancedRules: return "通用高级规则"
            }
        }
    }

    @MainActor
    private final class AdvancedRuleEditor: NSObject, NSTextFieldDelegate {
        let view = NSStackView()
        private let enabledButton: NSButton
        private let targetButton: NSButton
        private let contentButton: NSButton
        private let titleField: NSTextField
        private let keywordField: NSTextField
        private let modePicker = NSPopUpButton()
        private let onChange: (SmartRewriteAutoRule) -> Void
        private let moveUp: () -> Void
        private let moveDown: () -> Void
        private var rule: SmartRewriteAutoRule

        init(
            rule: SmartRewriteAutoRule,
            onChange: @escaping (SmartRewriteAutoRule) -> Void,
            moveUp: @escaping () -> Void,
            moveDown: @escaping () -> Void
        ) {
            self.rule = rule
            self.onChange = onChange
            self.moveUp = moveUp
            self.moveDown = moveDown
            enabledButton = NSButton(
                checkboxWithTitle: "启用",
                target: nil,
                action: nil
            )
            targetButton = NSButton(
                checkboxWithTitle: "窗口",
                target: nil,
                action: nil
            )
            contentButton = NSButton(
                checkboxWithTitle: "口述",
                target: nil,
                action: nil
            )
            titleField = NSTextField(string: rule.title)
            keywordField = NSTextField(string: rule.keywordText)
            super.init()
            configure()
        }

        private func configure() {
            enabledButton.state = rule.isEnabled ? .on : .off
            targetButton.state = rule.matchTarget ? .on : .off
            contentButton.state = rule.matchContent ? .on : .off
            keywordField.placeholderString = "关键词，逗号分隔"
            titleField.placeholderString = "规则名称"
            titleField.delegate = self
            keywordField.delegate = self

            for mode in SmartRewriteAutoRuleStore.selectableModes {
                modePicker.addItem(withTitle: mode.displayName)
                modePicker.lastItem?.representedObject = mode.rawValue
            }
            modePicker.selectItem(withTitle: rule.mode.displayName)

            for control in [enabledButton, targetButton, contentButton, modePicker] {
                control.target = self
                control.action = #selector(controlChanged(_:))
            }

            let up = NSButton(
                image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "上移")
                    ?? NSImage(),
                target: self,
                action: #selector(moveUpTapped(_:))
            )
            let down = NSButton(
                image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "下移")
                    ?? NSImage(),
                target: self,
                action: #selector(moveDownTapped(_:))
            )
            up.bezelStyle = .inline
            down.bezelStyle = .inline

            let conditionRow = NSStackView(
                views: [enabledButton, targetButton, contentButton, modePicker, up, down]
            )
            conditionRow.orientation = .horizontal
            conditionRow.spacing = 8
            view.orientation = .vertical
            view.alignment = .leading
            view.spacing = 7
            view.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.separatorColor.cgColor
            view.addArrangedSubview(titleField)
            view.addArrangedSubview(conditionRow)
            view.addArrangedSubview(keywordField)
            titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            keywordField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            emit()
        }

        @objc private func controlChanged(_ sender: NSControl) {
            emit()
        }

        @objc private func moveUpTapped(_ sender: NSButton) {
            moveUp()
        }

        @objc private func moveDownTapped(_ sender: NSButton) {
            moveDown()
        }

        private func emit() {
            rule.title = titleField.stringValue
            rule.keywordText = keywordField.stringValue
            rule.isEnabled = enabledButton.state == .on
            rule.matchTarget = targetButton.state == .on
            rule.matchContent = contentButton.state == .on
            if let rawValue = modePicker.selectedItem?.representedObject as? String,
               let mode = RewriteMode(rawValue: rawValue) {
                rule.mode = mode
            }
            onChange(rule)
        }
    }

    private let editorModel: ApplicationScopeEditorModel
    private let catalog: ApplicationCatalogLoading
    private let sidebarItems: [SidebarItem] = [
        .category(.recent),
        .category(.communication),
        .category(.productivity),
        .category(.development),
        .category(.browser),
        .category(.other),
        .category(.all),
        .advancedRules,
    ]
    private let sidebarTable = NSTableView()
    private let applicationTable = NSTableView()
    private let searchField = NSSearchField()
    private let configuredOnlyButton = NSButton(
        checkboxWithTitle: "仅看已配置",
        target: nil,
        action: nil
    )
    private let detailStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "正在读取应用…")
    private weak var splitView: NSSplitView?
    private weak var applicationListPane: NSView?
    private var applicationListWidthBeforeAdvanced: CGFloat = 420
    private var loadTask: Task<Void, Never>?
    private var iconCache: [URL: NSImage] = [:]
    private var advancedRuleEditors: [AdvancedRuleEditor] = []
    var summaryDidChange: ((String) -> Void)?

    init(
        editorModel: ApplicationScopeEditorModel,
        catalog: ApplicationCatalogLoading
    ) {
        self.editorModel = editorModel
        self.catalog = catalog
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        buildInterface()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadAll()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let items = await catalog.load()
            guard !Task.isCancelled else { return }
            editorModel.setApplications(items)
            emptyLabel.stringValue = items.isEmpty ? "没有找到可用应用" : ""
            reloadAll()
        }
    }

    func setSection(_ section: ApplicationScopeSection) {
        editorModel.selectedSection = section
        editorModel.selectedBundleIdentifiers.removeAll()
        configuredOnlyButton.state = editorModel.showsConfiguredOnly ? .on : .off
        applicationTable.deselectAll(nil)
        reloadAll()
    }

    func cancelLoading() {
        loadTask?.cancel()
        catalog.cancel()
    }

    private func buildInterface() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = makeSidebar()
        let applicationList = makeApplicationList()
        let detail = makeDetailPanel()
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(applicationList)
        splitView.addArrangedSubview(detail)
        self.splitView = splitView
        applicationListPane = applicationList
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 2)

        view.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 125),
            applicationList.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            detail.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }

    private func makeSidebar() -> NSView {
        configureTable(sidebarTable, identifier: "sidebar", rowHeight: 34)
        sidebarTable.allowsMultipleSelection = false
        sidebarTable.selectRowIndexes(IndexSet(integer: 6), byExtendingSelection: false)
        let scroll = scrollView(for: sidebarTable)
        let container = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeApplicationList() -> NSView {
        searchField.placeholderString = "搜索应用或 Bundle ID"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        configuredOnlyButton.target = self
        configuredOnlyButton.action = #selector(configuredOnlyChanged(_:))

        configureTable(applicationTable, identifier: "applications", rowHeight: 52)
        applicationTable.allowsMultipleSelection = true
        applicationTable.rowHeight = 52
        let scroll = scrollView(for: applicationTable)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        let controls = NSStackView(views: [searchField, configuredOnlyButton])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        configuredOnlyButton.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(controls)
        container.addSubview(scroll)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            searchField.widthAnchor.constraint(equalTo: controls.widthAnchor),

            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        return container
    }

    private func makeDetailPanel() -> NSView {
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 12
        detailStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        detailStack.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(detailStack)
        NSLayoutConstraint.activate([
            detailStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            detailStack.topAnchor.constraint(equalTo: document.topAnchor),
            detailStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        return scroll
    }

    private func configureTable(
        _ table: NSTableView,
        identifier: String,
        rowHeight: CGFloat
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.delegate = self
        table.dataSource = self
        table.style = .sourceList
    }

    private func scrollView(for table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = table
        return scroll
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        editorModel.query = sender.stringValue
        reloadApplications()
    }

    @objc private func configuredOnlyChanged(_ sender: NSButton) {
        editorModel.showsConfiguredOnly = sender.state == .on
        reloadApplications()
    }

    private func reloadAll() {
        sidebarTable.reloadData()
        reloadApplications()
        rebuildDetail()
    }

    private func reloadApplications() {
        applicationTable.reloadData()
        restoreSelection()
        updateSummary()
    }

    private func restoreSelection() {
        let indexes = IndexSet(
            editorModel.visibleApplications.enumerated().compactMap {
                editorModel.selectedBundleIdentifiers.contains(
                    $0.element.bundleIdentifier
                ) ? $0.offset : nil
            }
        )
        applicationTable.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    private func rebuildDetail() {
        let showsAdvancedRules = selectedSidebarItem == .advancedRules
        updatePaneLayout(showsAdvancedRules: showsAdvancedRules)

        detailStack.arrangedSubviews.forEach {
            detailStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        advancedRuleEditors.removeAll()

        if showsAdvancedRules {
            buildAdvancedRules()
        } else {
            buildApplicationDetail()
        }
        updateSummary()
    }

    private func updatePaneLayout(showsAdvancedRules: Bool) {
        guard let splitView, let applicationListPane else { return }
        if showsAdvancedRules {
            if !applicationListPane.isHidden {
                applicationListWidthBeforeAdvanced = max(
                    applicationListPane.frame.width,
                    420
                )
            }
            applicationListPane.isHidden = true
            splitView.adjustSubviews()
            return
        }

        guard applicationListPane.isHidden else { return }
        applicationListPane.isHidden = false
        splitView.adjustSubviews()
        let sidebarWidth = splitView.subviews.first?.frame.width ?? 125
        let restoredPosition =
            ApplicationScopePaneSizing.restoredApplicationDividerPosition(
                totalWidth: splitView.bounds.width,
                sidebarWidth: sidebarWidth,
                previousApplicationWidth: applicationListWidthBeforeAdvanced,
                minimumDetailWidth: 260,
                dividerThickness: splitView.dividerThickness
            )
        splitView.setPosition(restoredPosition, ofDividerAt: 1)
    }

    private func buildApplicationDetail() {
        let selected = editorModel.applications.filter {
            editorModel.selectedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let title = heading(
            selected.isEmpty
                ? "选择应用"
                : selected.count == 1
                    ? selected[0].displayName
                    : "已选择 \(selected.count) 个应用"
        )
        detailStack.addArrangedSubview(title)

        if editorModel.selectedSection == .autoSend {
            let toggle = NSButton(
                checkboxWithTitle: "启用粘贴后自动发送",
                target: self,
                action: #selector(autoSendEnabledChanged(_:))
            )
            toggle.state = editorModel.draft.autoSendConfiguration.isEnabled
                ? .on
                : .off
            detailStack.addArrangedSubview(toggle)
        }

        guard !selected.isEmpty else {
            detailStack.addArrangedSubview(hint("可在中间列表多选应用后批量设置。"))
            return
        }

        let picker = NSPopUpButton()
        if editorModel.selectedSection == .rewrite {
            picker.addItem(withTitle: "未指定")
            picker.lastItem?.representedObject = ""
            for mode in SmartRewriteAutoRuleStore.selectableModes {
                picker.addItem(withTitle: mode.displayName)
                picker.lastItem?.representedObject = mode.rawValue
            }
            picker.target = self
            picker.action = #selector(rewriteModeChanged(_:))
            selectCommonRewriteMode(in: picker, items: selected)
            detailStack.addArrangedSubview(heading("默认整理模式"))
            detailStack.addArrangedSubview(picker)
            detailStack.addArrangedSubview(
                hint("高级规则优先；未指定时继续使用通用规则和默认模式。")
            )
        } else {
            [
                ("关闭", PostPasteAction.none.rawValue),
                ("回车", PostPasteAction.returnKey.rawValue),
                ("Command + 回车", PostPasteAction.commandReturn.rawValue),
            ].forEach {
                picker.addItem(withTitle: $0.0)
                picker.lastItem?.representedObject = $0.1
            }
            picker.target = self
            picker.action = #selector(autoSendActionChanged(_:))
            selectCommonAutoSendAction(in: picker, items: selected)
            detailStack.addArrangedSubview(heading("粘贴后的动作"))
            detailStack.addArrangedSubview(picker)
            detailStack.addArrangedSubview(
                hint("仅普通听写成功粘贴后执行；翻译、闪念和 OpenClaw 不执行。")
            )
        }
    }

    private func buildAdvancedRules() {
        detailStack.addArrangedSubview(heading("通用高级规则"))
        detailStack.addArrangedSubview(
            hint("按当前顺序匹配窗口或口述关键词，命中后优先于应用默认设置。")
        )
        for index in editorModel.draft.rewriteConfiguration.rules.indices {
            let rule = editorModel.draft.rewriteConfiguration.rules[index]
            let editor = AdvancedRuleEditor(
                rule: rule,
                onChange: { [weak self] updated in
                    self?.updateRule(updated, at: index)
                },
                moveUp: { [weak self] in self?.moveRule(at: index, offset: -1) },
                moveDown: { [weak self] in self?.moveRule(at: index, offset: 1) }
            )
            advancedRuleEditors.append(editor)
            detailStack.addArrangedSubview(editor.view)
            editor.view.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        }

        let fallbackPicker = NSPopUpButton()
        for mode in SmartRewriteAutoRuleStore.selectableModes {
            fallbackPicker.addItem(withTitle: mode.displayName)
            fallbackPicker.lastItem?.representedObject = mode.rawValue
        }
        fallbackPicker.selectItem(
            withTitle: editorModel.draft.rewriteConfiguration.fallbackMode.displayName
        )
        fallbackPicker.target = self
        fallbackPicker.action = #selector(fallbackModeChanged(_:))
        detailStack.addArrangedSubview(heading("未匹配时"))
        detailStack.addArrangedSubview(fallbackPicker)
    }

    private func updateRule(_ rule: SmartRewriteAutoRule, at index: Int) {
        guard editorModel.draft.rewriteConfiguration.rules.indices.contains(index) else {
            return
        }
        editorModel.updateDraft {
            $0.rewriteConfiguration.rules[index] = rule
        }
    }

    private func moveRule(at index: Int, offset: Int) {
        let target = index + offset
        guard editorModel.draft.rewriteConfiguration.rules.indices.contains(index),
              editorModel.draft.rewriteConfiguration.rules.indices.contains(target) else {
            return
        }
        editorModel.updateDraft {
            $0.rewriteConfiguration.rules.swapAt(index, target)
        }
        rebuildDetail()
    }

    @objc private func rewriteModeChanged(_ sender: NSPopUpButton) {
        let mode = (sender.selectedItem?.representedObject as? String)
            .flatMap(RewriteMode.init(rawValue:))
        editorModel.updateDraft {
            $0.setRewriteMode(
                mode,
                for: Array(editorModel.selectedBundleIdentifiers)
            )
        }
        reloadApplications()
        rebuildDetail()
    }

    @objc private func autoSendEnabledChanged(_ sender: NSButton) {
        editorModel.updateDraft {
            $0.autoSendConfiguration.isEnabled = sender.state == .on
        }
        updateSummary()
    }

    @objc private func autoSendActionChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let action = PostPasteAction(rawValue: rawValue) else {
            return
        }
        editorModel.updateDraft {
            $0.setAutoSendAction(
                action,
                for: Array(editorModel.selectedBundleIdentifiers)
            )
        }
        reloadApplications()
        rebuildDetail()
    }

    @objc private func fallbackModeChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = RewriteMode(rawValue: rawValue) else {
            return
        }
        editorModel.updateDraft {
            $0.rewriteConfiguration.fallbackMode = mode
        }
    }

    private func selectCommonRewriteMode(
        in picker: NSPopUpButton,
        items: [ApplicationCatalogItem]
    ) {
        let values = Set(items.map {
            editorModel.draft.rewriteConfiguration
                .appModesByBundleID[$0.bundleIdentifier]?.rawValue ?? ""
        })
        guard values.count == 1, let value = values.first else {
            picker.addItem(withTitle: "多种设置")
            picker.lastItem?.representedObject = NSNull()
            picker.selectItem(at: picker.numberOfItems - 1)
            return
        }
        if let index = picker.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == value
        }) {
            picker.selectItem(at: index)
        }
    }

    private func selectCommonAutoSendAction(
        in picker: NSPopUpButton,
        items: [ApplicationCatalogItem]
    ) {
        let values = Set(items.map {
            editorModel.draft.autoSendConfiguration
                .actionsByBundleID[$0.bundleIdentifier]?.rawValue
                ?? PostPasteAction.none.rawValue
        })
        guard values.count == 1, let value = values.first else {
            picker.addItem(withTitle: "多种设置")
            picker.lastItem?.representedObject = NSNull()
            picker.selectItem(at: picker.numberOfItems - 1)
            return
        }
        if let index = picker.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == value
        }) {
            picker.selectItem(at: index)
        }
    }

    private func updateSummary() {
        let selected = editorModel.selectedBundleIdentifiers.count
        let configured: Int
        switch editorModel.selectedSection {
        case .rewrite:
            configured = editorModel.draft.rewriteConfiguration
                .appModesByBundleID.count
        case .autoSend:
            configured = editorModel.draft.autoSendConfiguration
                .actionsByBundleID.count
        }
        summaryDidChange?("已选择 \(selected) 个应用 · 已配置 \(configured) 个")
    }

    private var selectedSidebarItem: SidebarItem {
        let row = sidebarTable.selectedRow
        guard sidebarItems.indices.contains(row) else {
            return .category(.all)
        }
        return sidebarItems[row]
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func hint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        return label
    }
}

extension ApplicationScopeViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sidebarTable
            ? sidebarItems.count
            : editorModel.visibleApplications.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        if tableView === sidebarTable {
            let identifier = NSUserInterfaceItemIdentifier("ApplicationScopeSidebarCell")
            let cell = tableView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = identifier
            if cell.textField == nil {
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = sidebarItems[row].title
            return cell
        }

        let item = editorModel.visibleApplications[row]
        let identifier = NSUserInterfaceItemIdentifier("ApplicationScopeApplicationCell")
        let cell = tableView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? ApplicationScopeApplicationRowView
            ?? ApplicationScopeApplicationRowView()
        cell.identifier = identifier
        let icon = iconCache[item.bundleURL] ?? {
            let loaded = NSWorkspace.shared.icon(forFile: item.bundleURL.path)
            iconCache[item.bundleURL] = loaded
            return loaded
        }()
        cell.render(
            item: item,
            icon: icon,
            isSelected: editorModel.selectedBundleIdentifiers.contains(
                item.bundleIdentifier
            ),
            valueText: editorModel.valueText(for: item)
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView === sidebarTable {
            switch selectedSidebarItem {
            case .category(let category):
                editorModel.category = category
            case .advancedRules:
                break
            }
            reloadApplications()
            rebuildDetail()
            return
        }

        editorModel.selectedBundleIdentifiers = Set(
            applicationTable.selectedRowIndexes.compactMap { index in
                guard editorModel.visibleApplications.indices.contains(index) else {
                    return nil
                }
                return editorModel.visibleApplications[index].bundleIdentifier
            }
        )
        rebuildDetail()
    }

    func tableView(
        _ tableView: NSTableView,
        shouldSelectRow row: Int
    ) -> Bool {
        guard tableView === sidebarTable,
              sidebarItems.indices.contains(row),
              sidebarItems[row] == .advancedRules else {
            return true
        }
        return editorModel.selectedSection == .rewrite
    }
}
