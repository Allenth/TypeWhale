import Foundation

struct RemoteInputSettingsStore {
    static let enabledKey = "typewhale.remote.enabled"
    static let mappingKey = "typewhale.remote.button-mapping.v1"
    static let mappingV2Key = "typewhale.remote.button-mapping.v2"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadEnabled() -> Bool {
        guard defaults.object(forKey: Self.enabledKey) != nil else { return true }
        return defaults.bool(forKey: Self.enabledKey)
    }

    func saveEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func loadMappings() -> RemoteButtonMapping {
        let v1Data = defaults.data(forKey: Self.mappingKey)
        let v1 = v1Data.flatMap(RemoteMappingMigration.decodeV1)

        if let v2Data = defaults.data(forKey: Self.mappingV2Key) {
            guard let v2 = RemoteMappingMigration.decodeV2(v2Data) else {
                return RemoteMappingMigration.makeMapping(v2: nil, v1: v1)
            }
            return RemoteMappingMigration.makeMapping(v2: v2, v1: v1)
        }

        guard let v1 else { return .defaults }
        let migrated = RemoteMappingMigration.makeMapping(v2: nil, v1: v1)
        if let v2Data = RemoteMappingMigration.encodeV2(migrated) {
            defaults.set(v2Data, forKey: Self.mappingV2Key)
        }
        return migrated
    }

    func saveMappings(_ mappings: RemoteButtonMapping) {
        guard let v2Data = RemoteMappingMigration.encodeV2(mappings),
              let v1Data = RemoteMappingMigration.encodeV1(mappings) else { return }
        defaults.set(v2Data, forKey: Self.mappingV2Key)
        defaults.set(v1Data, forKey: Self.mappingKey)
    }
}
