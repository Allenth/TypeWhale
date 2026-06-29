import AppKit

enum AppPaths {
    static let fileManager = FileManager.default
    static let resources = Bundle.main.resourceURL!
    static let caches = userDirectory(.cachesDirectory)
    static let recordings = caches.appendingPathComponent("Recordings")
    static let models: URL = {
        if let override = ProcessInfo.processInfo.environment["TYPESPEAKER_MODELS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return userDirectory(.applicationSupportDirectory).appendingPathComponent("Models")
    }()

    static func prepare() throws {
        for directory in [recordings, models] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func userDirectory(_ directory: FileManager.SearchPathDirectory) -> URL {
        fileManager.urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhale", isDirectory: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var lifecycle = AppLifecycleCoordinator(controller: MainViewController())
    private var controller: MainViewController { lifecycle.controller }
    private lazy var speechInput = SpeechInputCoordinator(
        controller: controller,
        showMainWindow: { [weak self] in self?.lifecycle.showMainWindow() },
        hideMainWindow: { [weak self] in self?.lifecycle.hideMainWindow() },
        shouldKeepMainWindowVisibleForScreenshot: { [weak self] in
            self?.lifecycle.shouldKeepMainWindowVisibleForScreenshot() ?? false
        }
    )

    override init() {
        LaunchDiagnostics.mark("AppDelegate init")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDiagnostics.mark("applicationDidFinishLaunching begin")
        LaunchDiagnostics.pruneOldLogs(keepingDays: 14)
        TypeWhaleApplication.terminateStaleInstances()
        LaunchDiagnostics.mark("lifecycle.setup begin")
        lifecycle.setup()
        lifecycle.onSystemWillSleep = { [weak self] in
            self?.speechInput.handleSystemWillSleep()
        }
        lifecycle.onSystemDidWake = { [weak self] in
            self?.speechInput.handleSystemDidWake()
        }
        lifecycle.onSystemWillPowerOff = { [weak self] in
            self?.speechInput.handleSystemWillPowerOff()
        }
        lifecycle.onMainInterfaceOpened = { [weak self] in
            self?.speechInput.refreshUserVisibleDiagnostics()
        }
        LaunchDiagnostics.mark("lifecycle.setup done")
        do {
            LaunchDiagnostics.mark("AppPaths.prepare begin")
            try AppPaths.prepare()
            LaunchDiagnostics.mark("AppPaths.prepare done")
        } catch {
            LaunchDiagnostics.mark("AppPaths.prepare failed: \(error.localizedDescription)")
            controller.status.stringValue = "无法准备应用目录"
            controller.detail.stringValue = error.localizedDescription
        }

        LaunchDiagnostics.mark("speechInput.start begin")
        speechInput.start()
        LaunchDiagnostics.mark("speechInput.start done")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lifecycle.shouldHandleReopen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        speechInput.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lifecycle.shouldTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

}

@main
enum TypeWhaleApplication {
    /// 单实例保护：刚启动的实例（最新二进制）接管，强制结束其它更早启动的同包实例，
    /// 避免出现多个 TypeWhale 同时抢全局快捷键、重复调用 DeepSeek 造成幽灵进程偷偷计费。
    @MainActor
    static func terminateStaleInstances() {
        let me = NSRunningApplication.current
        let myStart = me.launchDate ?? Date()
        func others() -> [NSRunningApplication] {
            NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == me.bundleIdentifier && $0.processIdentifier != me.processIdentifier
            }
        }
        let stale = others().filter { ($0.launchDate ?? .distantPast) < myStart }
        LaunchDiagnostics.mark("single-instance: check others=\(others().count) stale=\(stale.count)")
        guard !stale.isEmpty else { return }
        for instance in stale {
            LaunchDiagnostics.mark("single-instance: forceTerminate stale pid=\(instance.processIdentifier)")
            instance.forceTerminate()
        }
        // 等残留实例退出（最多 ~2 秒），确保不会新旧并存重复触发。
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, !others().isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    @MainActor
    static func main() {
        CrashReporter.install()
        LaunchDiagnostics.mark("main begin")
        let app = NSApplication.shared
        LaunchDiagnostics.mark("NSApplication.shared ready")
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        LaunchDiagnostics.mark("app.run begin")
        app.run()
    }
}
