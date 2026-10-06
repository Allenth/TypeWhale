import Foundation
import IOKit.hid
import IOKit.hidsystem

struct RemotePowerUsageMapping: Equatable {
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"

    let source: UInt64
    let destination: UInt64

    init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }

    init?(property: [String: NSNumber]) {
        guard let source = property[Self.sourceKey],
              let destination = property[Self.destinationKey] else { return nil }
        self.source = source.uint64Value
        self.destination = destination.uint64Value
    }

    var property: [String: NSNumber] {
        [
            Self.sourceKey: NSNumber(value: source),
            Self.destinationKey: NSNumber(value: destination),
        ]
    }
}

enum RemotePowerKeyMappingPolicy {
    static let powerSource: UInt64 = 0x0000_0007_0000_0066
    static let neutralF20Mapping = RemotePowerUsageMapping(
        source: powerSource,
        destination: 0x0000_0007_0000_006F
    )

    static func replacingPowerMapping(
        in mappings: [RemotePowerUsageMapping],
        with replacement: RemotePowerUsageMapping?
    ) -> [RemotePowerUsageMapping] {
        let retained = mappings.filter { $0.source != powerSource }
        return replacement.map { retained + [$0] } ?? retained
    }
}

struct RemotePowerKeyService {
    let registryID: UInt64?
    private let retainedOwner: AnyObject?
    let readMappings: () -> [RemotePowerUsageMapping]
    let writeMappings: ([RemotePowerUsageMapping]) -> Bool

    init(
        registryID: UInt64?,
        retainedOwner: AnyObject? = nil,
        readMappings: @escaping () -> [RemotePowerUsageMapping],
        writeMappings: @escaping ([RemotePowerUsageMapping]) -> Bool
    ) {
        self.registryID = registryID
        self.retainedOwner = retainedOwner
        self.readMappings = readMappings
        self.writeMappings = writeMappings
    }
}

final class RemotePowerKeyNeutralizer {
    typealias ServiceProvider = () -> [RemotePowerKeyService]

    private struct OriginalPowerMapping {
        let value: RemotePowerUsageMapping?
    }

    private let serviceProvider: ServiceProvider
    private var originals: [UInt64: OriginalPowerMapping] = [:]
    private(set) var isNeutralized = false

    init(serviceProvider: @escaping ServiceProvider = RemotePowerKeyNeutralizer.systemServices) {
        self.serviceProvider = serviceProvider
    }

    @discardableResult
    func setNeutralized(_ shouldNeutralize: Bool) -> Bool {
        if shouldNeutralize == isNeutralized {
            return true
        }
        return shouldNeutralize ? applyNeutralMapping() : restoreOriginalMappings()
    }

    private func applyNeutralMapping() -> Bool {
        let services = serviceProvider()
        guard !services.isEmpty else { return false }

        var snapshots: [UInt64: [RemotePowerUsageMapping]] = [:]
        var appliedIDs: [UInt64] = []
        var newlyCapturedIDs: [UInt64] = []

        for service in services {
            guard let id = service.registryID else {
                rollback(
                    services: services,
                    snapshots: snapshots,
                    appliedIDs: appliedIDs,
                    neutralizedAfterRollback: false
                )
                newlyCapturedIDs.forEach { originals.removeValue(forKey: $0) }
                return false
            }
            let current = service.readMappings()
            snapshots[id] = current
            if originals[id] == nil {
                originals[id] = OriginalPowerMapping(
                    value: current.first { $0.source == RemotePowerKeyMappingPolicy.powerSource }
                )
                newlyCapturedIDs.append(id)
            }
            let desired = RemotePowerKeyMappingPolicy.replacingPowerMapping(
                in: current,
                with: RemotePowerKeyMappingPolicy.neutralF20Mapping
            )
            guard service.writeMappings(desired) else {
                rollback(
                    services: services,
                    snapshots: snapshots,
                    appliedIDs: appliedIDs,
                    neutralizedAfterRollback: false
                )
                newlyCapturedIDs.forEach { originals.removeValue(forKey: $0) }
                return false
            }
            appliedIDs.append(id)
        }

        isNeutralized = true
        return true
    }

    private func restoreOriginalMappings() -> Bool {
        guard isNeutralized else { return true }
        let services = serviceProvider()
        let servicesByID = Dictionary(uniqueKeysWithValues: services.compactMap { service in
            service.registryID.map { ($0, service) }
        })
        guard originals.keys.allSatisfy({ servicesByID[$0] != nil }) else { return false }

        var snapshots: [UInt64: [RemotePowerUsageMapping]] = [:]
        var restoredIDs: [UInt64] = []
        for (id, original) in originals {
            guard let service = servicesByID[id] else { return false }
            let current = service.readMappings()
            snapshots[id] = current
            let desired = RemotePowerKeyMappingPolicy.replacingPowerMapping(
                in: current,
                with: original.value
            )
            guard service.writeMappings(desired) else {
                rollback(
                    services: services,
                    snapshots: snapshots,
                    appliedIDs: restoredIDs,
                    neutralizedAfterRollback: true
                )
                return false
            }
            restoredIDs.append(id)
        }

        originals.removeAll()
        isNeutralized = false
        return true
    }

    private func rollback(
        services: [RemotePowerKeyService],
        snapshots: [UInt64: [RemotePowerUsageMapping]],
        appliedIDs: [UInt64],
        neutralizedAfterRollback: Bool
    ) {
        let servicesByID = Dictionary(uniqueKeysWithValues: services.compactMap { service in
            service.registryID.map { ($0, service) }
        })
        for id in appliedIDs {
            guard let service = servicesByID[id], let snapshot = snapshots[id] else { continue }
            _ = service.writeMappings(snapshot)
        }
        isNeutralized = neutralizedAfterRollback
    }

    private static func systemServices() -> [RemotePowerKeyService] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let candidates = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return candidates.compactMap { service in
            guard matchesRC003(service),
                  let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber else {
                return nil
            }
            return RemotePowerKeyService(
                registryID: id.uint64Value,
                retainedOwner: client,
                readMappings: {
                    let raw = IOHIDServiceClientCopyProperty(
                        service,
                        "UserKeyMapping" as CFString
                    ) as? [[String: NSNumber]] ?? []
                    return raw.compactMap(RemotePowerUsageMapping.init(property:))
                },
                writeMappings: { mappings in
                    IOHIDServiceClientSetProperty(
                        service,
                        "UserKeyMapping" as CFString,
                        mappings.map(\.property) as CFArray
                    )
                }
            )
        }
    }

    private static func matchesRC003(_ service: IOHIDServiceClient) -> Bool {
        let vendor = IOHIDServiceClientCopyProperty(
            service,
            kIOHIDVendorIDKey as CFString
        ) as? NSNumber
        let product = IOHIDServiceClientCopyProperty(
            service,
            kIOHIDProductIDKey as CFString
        ) as? NSNumber
        return vendor?.intValue == XiaomiRemote2ProHIDProfile.vendorID &&
            product?.intValue == XiaomiRemote2ProHIDProfile.productID
    }
}
