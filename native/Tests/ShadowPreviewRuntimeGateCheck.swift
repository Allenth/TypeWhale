import Foundation

@main
struct ShadowPreviewRuntimeGateCheck {
    static func main() {
        blocksStartWhenDiagnosticSwitchIsOff()
        blocksPublishWhenDiagnosticSwitchIsOff()
        allowsRuntimeOnlyWhenDiagnosticSwitchIsOn()
        print("ShadowPreviewRuntimeGateCheck passed")
    }

    private static func blocksStartWhenDiagnosticSwitchIsOff() {
        precondition(ShadowPreviewRuntimeGate.shouldStart(isEnabled: false) == false)
    }

    private static func blocksPublishWhenDiagnosticSwitchIsOff() {
        precondition(ShadowPreviewRuntimeGate.shouldPublish(isEnabled: false, hasRuntime: true) == false)
    }

    private static func allowsRuntimeOnlyWhenDiagnosticSwitchIsOn() {
        precondition(ShadowPreviewRuntimeGate.shouldStart(isEnabled: true) == true)
        precondition(ShadowPreviewRuntimeGate.shouldPublish(isEnabled: true, hasRuntime: false) == false)
        precondition(ShadowPreviewRuntimeGate.shouldPublish(isEnabled: true, hasRuntime: true) == true)
    }
}
