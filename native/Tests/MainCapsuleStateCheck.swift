import Foundation

@main
struct MainCapsuleStateCheck {
    static func main() {
        mapsRecordingPhase()
        mapsProcessingPhases()
        mapsPurposeAppearance()
        carriesContextAndIndicators()
        print("MainCapsuleStateCheck passed")
    }

    private static func mapsRecordingPhase() {
        let state = MainCapsuleState.recording(
            instructions: "再次按下 Fn 完成录音",
            purpose: .dictation,
            context: MainCapsuleContext(targetAppName: "ChatGPT")
        )

        precondition(state.phase == .recording(instructions: "再次按下 Fn 完成录音"))
        precondition(state.purpose == .dictation)
        precondition(state.context.targetAppName == "ChatGPT")
    }

    private static func mapsProcessingPhases() {
        let phases: [MainCapsulePhase] = [
            .detectingSpeech,
            .recognizing,
            .rewriting,
            .translating,
            .longFormFinishing(message: "请稍候..."),
            .autoFinished(message: "正在识别"),
            .empty(reason: "未检测到人声"),
            .failed(message: "识别失败"),
            .hidden
        ]

        for phase in phases {
            let state = MainCapsuleState(phase: phase)
            precondition(state.phase == phase)
        }
    }

    private static func mapsPurposeAppearance() {
        precondition(MainCapsulePurposeAppearance(purpose: .dictation).modeName == "")
        precondition(MainCapsulePurposeAppearance(purpose: .ideaPill).modeName == "闪念胶囊")

        let openClaw = MainCapsulePurposeAppearance(
            purpose: .openClawChat,
            openClawConnection: .connected
        )
        precondition(openClaw == .openClaw(connection: .connected))
        precondition(openClaw.modeName == "OpenClaw")
    }

    private static func carriesContextAndIndicators() {
        let state = MainCapsuleState(
            phase: .recording(instructions: nil),
            purpose: .openClaw(connection: .checking),
            context: MainCapsuleContext(
                targetAppName: "Xcode",
                modeName: "自动",
                autoTranslateEnabled: true
            ),
            indicators: MainCapsuleIndicators(
                remainingSeconds: 18,
                memoryHigh: true
            )
        )

        precondition(state.context.targetAppName == "Xcode")
        precondition(state.context.modeName == "自动")
        precondition(state.context.autoTranslateEnabled)
        precondition(state.indicators.remainingSeconds == 18)
        precondition(state.indicators.memoryHigh)
    }
}
