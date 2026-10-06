import Foundation

struct ShadowPreviewRuntimeGate: Equatable {
    static func shouldStart(isEnabled: Bool) -> Bool {
        isEnabled
    }

    static func shouldPublish(isEnabled: Bool, hasRuntime: Bool) -> Bool {
        isEnabled && hasRuntime
    }
}
