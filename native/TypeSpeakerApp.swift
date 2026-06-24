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
        LaunchDiagnostics.mark("lifecycle.setup begin")
        lifecycle.setup()
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
