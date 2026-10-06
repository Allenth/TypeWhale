import Foundation

@main
enum RemotePowerKeyNeutralizerCheck {
    static func main() {
        appliesAndRestoresWithoutTouchingOtherMappings()
        rollsBackEveryServiceOnPartialFailure()
        keepsNeutralizedStateWhenRestoreFails()
        refusesToClaimSuccessWithoutATargetService()
        print("RemotePowerKeyNeutralizerCheck passed")
    }

    private static func appliesAndRestoresWithoutTouchingOtherMappings() {
        let other = RemotePowerUsageMapping(source: 11, destination: 12)
        let originalPower = RemotePowerUsageMapping(
            source: RemotePowerKeyMappingPolicy.powerSource,
            destination: 99
        )
        var serviceOne = [other, originalPower]
        var serviceTwo = [other]
        let neutralizer = RemotePowerKeyNeutralizer(serviceProvider: {
            [
                RemotePowerKeyService(
                    registryID: 1,
                    readMappings: { serviceOne },
                    writeMappings: { serviceOne = $0; return true }
                ),
                RemotePowerKeyService(
                    registryID: 2,
                    readMappings: { serviceTwo },
                    writeMappings: { serviceTwo = $0; return true }
                ),
            ]
        })

        precondition(neutralizer.setNeutralized(true))
        precondition(neutralizer.isNeutralized)
        precondition(serviceOne.contains(other))
        precondition(serviceTwo.contains(other))
        precondition(serviceOne.contains(RemotePowerKeyMappingPolicy.neutralF20Mapping))
        precondition(serviceTwo.contains(RemotePowerKeyMappingPolicy.neutralF20Mapping))
        precondition(!serviceOne.contains(originalPower))

        precondition(neutralizer.setNeutralized(false))
        precondition(!neutralizer.isNeutralized)
        precondition(serviceOne.contains(originalPower))
        precondition(serviceTwo == [other])
    }

    private static func rollsBackEveryServiceOnPartialFailure() {
        let firstOriginal = [RemotePowerUsageMapping(source: 21, destination: 22)]
        let secondOriginal = [RemotePowerUsageMapping(source: 31, destination: 32)]
        var first = firstOriginal
        var second = secondOriginal
        let neutralizer = RemotePowerKeyNeutralizer(serviceProvider: {
            [
                RemotePowerKeyService(
                    registryID: 3,
                    readMappings: { first },
                    writeMappings: { first = $0; return true }
                ),
                RemotePowerKeyService(
                    registryID: 4,
                    readMappings: { second },
                    writeMappings: { mappings in
                        if mappings.contains(RemotePowerKeyMappingPolicy.neutralF20Mapping) {
                            return false
                        }
                        second = mappings
                        return true
                    }
                ),
            ]
        })

        precondition(!neutralizer.setNeutralized(true))
        precondition(!neutralizer.isNeutralized)
        precondition(first == firstOriginal)
        precondition(second == secondOriginal)
    }

    private static func refusesToClaimSuccessWithoutATargetService() {
        let neutralizer = RemotePowerKeyNeutralizer(serviceProvider: { [] })
        precondition(!neutralizer.setNeutralized(true))
        precondition(!neutralizer.isNeutralized)
        precondition(neutralizer.setNeutralized(false))
    }

    private static func keepsNeutralizedStateWhenRestoreFails() {
        var mappings: [RemotePowerUsageMapping] = []
        var rejectRestore = false
        let neutralizer = RemotePowerKeyNeutralizer(serviceProvider: {
            [RemotePowerKeyService(
                registryID: 5,
                readMappings: { mappings },
                writeMappings: { candidate in
                    if rejectRestore && !candidate.contains(RemotePowerKeyMappingPolicy.neutralF20Mapping) {
                        return false
                    }
                    mappings = candidate
                    return true
                }
            )]
        })
        precondition(neutralizer.setNeutralized(true))
        rejectRestore = true
        precondition(!neutralizer.setNeutralized(false))
        precondition(neutralizer.isNeutralized)
        precondition(mappings.contains(RemotePowerKeyMappingPolicy.neutralF20Mapping))
    }
}
