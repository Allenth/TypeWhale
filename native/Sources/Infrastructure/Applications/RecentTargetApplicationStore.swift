import AppKit
import Foundation

struct RecentTargetApplicationRecord: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL?
    let lastUsedAt: Date
}

enum RecentTargetApplicationStore {
    static let storageKey = "recentTargetApplications.v1"
    static let maximumRecordCount = 20

    static func load() -> [RecentTargetApplicationRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode(
                  [RecentTargetApplicationRecord].self,
                  from: data
              ) else {
            return []
        }
        return normalized(records)
    }

    static func record(
        _ app: NSRunningApplication,
        usedAt: Date = Date()
    ) {
        guard let bundleIdentifier = app.bundleIdentifier else { return }
        record(
            bundleIdentifier: bundleIdentifier,
            displayName: app.localizedName ?? bundleIdentifier,
            bundleURL: app.bundleURL,
            usedAt: usedAt
        )
    }

    static func record(
        bundleIdentifier: String,
        displayName: String,
        bundleURL: URL?,
        usedAt: Date
    ) {
        let bundleID = bundleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !bundleID.isEmpty else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = RecentTargetApplicationRecord(
            bundleIdentifier: bundleID,
            displayName: name.isEmpty ? bundleID : name,
            bundleURL: bundleURL,
            lastUsedAt: usedAt
        )
        var records = load().filter { $0.bundleIdentifier != bundleID }
        records.insert(record, at: 0)
        save(Array(records.prefix(maximumRecordCount)))
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func save(_ records: [RecentTargetApplicationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func normalized(
        _ records: [RecentTargetApplicationRecord]
    ) -> [RecentTargetApplicationRecord] {
        var seen = Set<String>()
        return records
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .filter { record in
                let bundleID = record.bundleIdentifier.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !bundleID.isEmpty, !seen.contains(bundleID) else {
                    return false
                }
                seen.insert(bundleID)
                return true
            }
            .prefix(maximumRecordCount)
            .map { $0 }
    }
}
