import AppKit

@MainActor
final class AppLifecycleCoordinator: NSObject, NSMenuDelegate {
    let controller: MainViewController
    private var statusItem: NSStatusItem?
    private let memoryStatusItem = NSMenuItem(title: "内存 -- MB", action: nil, keyEquivalent: "")
    private let versionStatusItem = NSMenuItem(title: "版本 --", action: nil, keyEquivalent: "")
    private var window: NSWindow?
    private var thirdPartyNoticesWindow: NSWindow?
    private var allowsTermination = false
    private var workspaceObserver: NSObjectProtocol?
    private let windowSize = NSSize(width: 920, height: 560)

    init(controller: MainViewController) {
        self.controller = controller
    }

    func setup() {
        LaunchDiagnostics.mark("observeSystemPowerOff begin")
        observeSystemPowerOff()
        LaunchDiagnostics.mark("setupMainMenu begin")
        setupMainMenu()
        LaunchDiagnostics.mark("setupStatusItem begin")
        setupStatusItem()
        LaunchDiagnostics.mark("setupMainWindow begin")
        setupMainWindow()
        LaunchDiagnostics.mark("showMainWindow begin")
        showMainWindow()
        LaunchDiagnostics.mark("AppLifecycleCoordinator setup done")
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    private func observeSystemPowerOff() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.allowsTermination = true
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let preferencesItem = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(.separator())
        let noticesItem = NSMenuItem(title: "第三方组件与模型授权", action: #selector(showThirdPartyNotices), keyEquivalent: "")
        noticesItem.target = self
        appMenu.addItem(noticesItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "隐藏 TypeWhale", action: #selector(hideMainWindow), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(closeMainWindow), keyEquivalent: "w")
        closeItem.target = self
        windowMenu.addItem(closeItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 30)
        statusItem = item
        if let button = item.button {
            button.title = ""
            button.image = makeStatusBarLogo()
            button.imagePosition = .imageOnly
            button.toolTip = "TypeWhale"
        }

        let menu = NSMenu()
        menu.delegate = self
        memoryStatusItem.isEnabled = false
        updateMemoryStatusItem()
        menu.addItem(memoryStatusItem)
        versionStatusItem.isEnabled = false
        updateVersionStatusItem()
        menu.addItem(versionStatusItem)
        menu.addItem(.separator())
        let showItem = NSMenuItem(title: "打开面板", action: #selector(openMainWindowFromStatusItem), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let noticesItem = NSMenuItem(title: "第三方组件与模型授权", action: #selector(showThirdPartyNotices), keyEquivalent: "")
        noticesItem.target = self
        menu.addItem(noticesItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "完全退出", action: #selector(quitFromStatusItem), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
    }

    private func makeStatusBarLogo() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 14))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: 22, height: 14)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSGradient(colors: [
            NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.08, alpha: 1),
        ])?.draw(in: path, angle: 90)
        NSColor(calibratedRed: 0.90, green: 0.60, blue: 0.02, alpha: 0.35).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let markColor = NSColor(calibratedRed: 0.43, green: 0.31, blue: 0.03, alpha: 1)
        markColor.setStroke()
        let wave = NSBezierPath()
        wave.lineWidth = 1.25
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        wave.move(to: NSPoint(x: 6.4, y: 6.0))
        wave.curve(
            to: NSPoint(x: 9.5, y: 6.0),
            controlPoint1: NSPoint(x: 7.3, y: 6.9),
            controlPoint2: NSPoint(x: 8.5, y: 5.1)
        )
        wave.curve(
            to: NSPoint(x: 12.9, y: 6.0),
            controlPoint1: NSPoint(x: 10.6, y: 6.9),
            controlPoint2: NSPoint(x: 11.7, y: 5.1)
        )
        wave.stroke()
        markColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14.8, y: 8.9, width: 2.2, height: 2.2)).fill()

        image.isTemplate = false
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMemoryStatusItem()
        updateVersionStatusItem()
        controller.updateMemoryReadout()
    }

    private func updateMemoryStatusItem() {
        let megabytes = MemoryMonitor.currentFootprintMB
        memoryStatusItem.title = "内存 \(megabytes) MB"
        switch MemoryMonitor.level(forMB: megabytes) {
        case .normal:
            memoryStatusItem.attributedTitle = NSAttributedString(
                string: memoryStatusItem.title,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        case .warn:
            memoryStatusItem.attributedTitle = NSAttributedString(
                string: "\(memoryStatusItem.title) · 偏高",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
        case .high:
            memoryStatusItem.attributedTitle = NSAttributedString(
                string: "\(memoryStatusItem.title) · 高",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
    }

    private func updateVersionStatusItem() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "--"
        let build = info?["CFBundleVersion"] as? String ?? "--"
        versionStatusItem.title = "版本 \(version) (\(build))"
        versionStatusItem.attributedTitle = NSAttributedString(
            string: versionStatusItem.title,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    private func setupMainWindow() {
        let mainWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "TypeWhale"
        mainWindow.appearance = NSAppearance(named: .darkAqua)
        mainWindow.isOpaque = false
        mainWindow.backgroundColor = .clear
        mainWindow.styleMask.insert(.fullSizeContentView)
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.titleVisibility = .hidden
        mainWindow.isMovableByWindowBackground = true
        mainWindow.contentViewController = controller
        mainWindow.contentView?.appearance = NSAppearance(named: .darkAqua)
        mainWindow.setContentSize(windowSize)
        mainWindow.contentMinSize = windowSize
        mainWindow.contentMaxSize = windowSize
        mainWindow.minSize = mainWindow.frame.size
        mainWindow.maxSize = mainWindow.frame.size
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()
        window = mainWindow
    }

    @objc private func closeMainWindow() {
        window?.performClose(nil)
    }

    @objc func hideMainWindow() {
        window?.orderOut(nil)
    }

    func shouldKeepMainWindowVisibleForScreenshot() -> Bool {
        guard let window, window.isVisible else { return false }
        return !window.isMiniaturized
    }

    @objc private func openMainWindowFromStatusItem() {
        showMainWindow()
    }

    @objc private func quitFromStatusItem() {
        allowsTermination = true
        NSApp.terminate(nil)
    }

    @objc private func showPreferences() {
        showMainWindow()
        controller.showPreferencesPopoverFromMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showThirdPartyNotices() {
        if thirdPartyNoticesWindow == nil {
            let content = ThirdPartyNoticesViewController()
            let noticesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            noticesWindow.title = "第三方组件与模型授权"
            noticesWindow.appearance = NSAppearance(named: .darkAqua)
            noticesWindow.contentViewController = content
            noticesWindow.contentView?.appearance = NSAppearance(named: .darkAqua)
            noticesWindow.setContentSize(NSSize(width: 560, height: 430))
            noticesWindow.contentMinSize = NSSize(width: 560, height: 430)
            noticesWindow.isReleasedWhenClosed = false
            noticesWindow.center()
            thirdPartyNoticesWindow = noticesWindow
        }
        guard let noticesWindow = thirdPartyNoticesWindow else { return }
        if noticesWindow.isMiniaturized {
            noticesWindow.deminiaturize(nil)
        }
        noticesWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func shouldHandleReopen() -> Bool {
        showMainWindow()
        return true
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        guard allowsTermination else {
            hideMainWindow()
            return .terminateCancel
        }
        return .terminateNow
    }
}
