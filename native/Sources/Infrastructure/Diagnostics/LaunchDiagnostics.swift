import Foundation

enum LaunchDiagnostics {
    private static let subsystem = "TypeWhale"

    /// 日志根目录：~/Library/Logs/TypeWhale
    static var baseDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(subsystem, isDirectory: true)
    }

    /// 当前 build 的日志文件：~/Library/Logs/TypeWhale/<YYYY-MM-DD>/<version>-<build>.log
    /// 每天一个文件夹、每个 build 一个文件；与 C 端 LaunchProbe 计算同一布局。
    static var logFileURL: URL {
        let day = dayFormatter.string(from: Date())
        return baseDirectory
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(appVersion)-\(appBuild).log")
    }

    /// 固定入口软链：~/Library/Logs/TypeWhale/latest.log → 当前 build 文件。
    static var latestSymlinkURL: URL {
        baseDirectory.appendingPathComponent("latest.log")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static func mark(_ message: String) {
        let url = logFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp) \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: .atomic)
                    refreshLatestSymlink(to: url)
                }
            }
        } catch {
            // Diagnostics must never prevent app launch.
        }
    }

    /// 把 latest.log 指向当前 build 文件（首次写入该文件时刷新一次）。
    private static func refreshLatestSymlink(to url: URL) {
        let link = latestSymlinkURL
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    }

    /// 删除超过 keepingDays 天的日志文件夹（按文件夹名 YYYY-MM-DD 判断）。启动时调用一次。
    /// 同时一次性清掉迁移前的旧单文件 launch.log（已不再写入）。
    static func pruneOldLogs(keepingDays: Int = 14) {
        let fm = FileManager.default
        try? fm.removeItem(at: baseDirectory.appendingPathComponent("launch.log"))
        guard let entries = try? fm.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date()) else { return }
        let cutoffName = dayFormatter.string(from: cutoff)
        for entry in entries {
            let name = entry.lastPathComponent
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            // 仅处理 YYYY-MM-DD 命名的日期文件夹；字符串比较即可正确排序。
            guard name.count == 10, dayFormatter.date(from: name) != nil else { continue }
            if name < cutoffName {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
