import Foundation

private final class CancellationProbe {
    private let lock = NSLock()
    private var value = false

    func markObserved() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var wasObserved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@main
struct ApplicationCatalogCheck {
    @MainActor
    static func main() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let installed = [
            InstalledApplicationMetadata(
                bundleIdentifier: "com.apple.dt.Xcode",
                displayName: "Xcode",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
                categoryIdentifier: "public.app-category.developer-tools"
            ),
            InstalledApplicationMetadata(
                bundleIdentifier: "com.apple.dt.Xcode",
                displayName: "Xcode Beta",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode-beta.app"),
                categoryIdentifier: "public.app-category.developer-tools"
            ),
            InstalledApplicationMetadata(
                bundleIdentifier: "com.tencent.xinWeChat",
                displayName: "微信",
                bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app"),
                categoryIdentifier: "public.app-category.social-networking"
            ),
            InstalledApplicationMetadata(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                bundleURL: URL(fileURLWithPath: "/System/Applications/Safari.app"),
                categoryIdentifier: nil
            ),
            InstalledApplicationMetadata(
                bundleIdentifier: "com.example.unknown",
                displayName: "Unknown",
                bundleURL: URL(fileURLWithPath: "/Applications/Unknown.app"),
                categoryIdentifier: nil
            ),
            InstalledApplicationMetadata(
                bundleIdentifier: "",
                displayName: "Invalid",
                bundleURL: URL(fileURLWithPath: "/Applications/Invalid.app"),
                categoryIdentifier: nil
            ),
        ]
        let recent = [
            RecentTargetApplicationRecord(
                bundleIdentifier: "com.example.customlocation",
                displayName: "Custom App",
                bundleURL: URL(fileURLWithPath: "/Users/Shared/Custom App.app"),
                lastUsedAt: base.addingTimeInterval(30)
            ),
            RecentTargetApplicationRecord(
                bundleIdentifier: "com.tencent.xinWeChat",
                displayName: "微信",
                bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app"),
                lastUsedAt: base.addingTimeInterval(10)
            ),
            RecentTargetApplicationRecord(
                bundleIdentifier: "com.apple.dt.Xcode",
                displayName: "Xcode",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
                lastUsedAt: base.addingTimeInterval(20)
            ),
        ]

        let catalog = ApplicationCatalog(
            installedLoader: { installed },
            recentLoader: { recent }
        )
        let items = await catalog.load()

        precondition(
            Set(items.map(\.bundleIdentifier)).count == items.count,
            "catalog must deduplicate by bundle ID"
        )
        precondition(
            items.filter {
                $0.bundleIdentifier == "com.apple.dt.Xcode"
            }.count == 1
        )
        precondition(
            items.first {
                $0.bundleIdentifier == "com.apple.dt.Xcode"
            }?.category == .development
        )
        precondition(
            items.first {
                $0.bundleIdentifier == "com.tencent.xinWeChat"
            }?.category == .communication
        )
        precondition(
            items.first {
                $0.bundleIdentifier == "com.apple.Safari"
            }?.category == .browser,
            "known browsers need a fallback when LSApplicationCategoryType is absent"
        )
        precondition(
            items.first {
                $0.bundleIdentifier == "com.example.unknown"
            }?.category == .other
        )
        precondition(
            items.first?.bundleIdentifier == "com.example.customlocation",
            "recently used apps should sort first by recency"
        )
        precondition(
            items.first?.lastUsedAt == base.addingTimeInterval(30)
        )
        precondition(
            items.contains {
                $0.bundleIdentifier == "com.example.customlocation"
            },
            "recent targets outside standard application roots must remain selectable"
        )
        precondition(
            !items.contains { $0.bundleIdentifier.isEmpty },
            "apps without a bundle ID must be excluded"
        )

        catalog.cancel()

        let cancellationProbe = CancellationProbe()
        let cancellableCatalog = ApplicationCatalog(
            installedLoader: {
                while !Task.isCancelled {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                cancellationProbe.markObserved()
                return []
            },
            recentLoader: { [] }
        )
        let loading = Task { await cancellableCatalog.load() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        cancellableCatalog.cancel()
        let cancelledResult = await loading.value
        precondition(cancelledResult.isEmpty)
        precondition(
            cancellationProbe.wasObserved,
            "cancel must propagate to the detached application scan"
        )

        print("ApplicationCatalogCheck passed")
    }
}
