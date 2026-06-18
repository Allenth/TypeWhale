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
    private let lifecycle = AppLifecycleCoordinator(controller: MainViewController())
    private var controller: MainViewController { lifecycle.controller }
    private lazy var speechInput = SpeechInputCoordinator(
        controller: controller,
        showMainWindow: { [weak self] in self?.lifecycle.showMainWindow() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycle.setup()
        do {
            try AppPaths.prepare()
        } catch {
            controller.status.stringValue = "无法准备应用目录"
            controller.detail.stringValue = error.localizedDescription
        }

        speechInput.start()
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
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
