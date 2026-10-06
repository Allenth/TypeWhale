import Foundation

@main
struct MainCapsuleLegacyStatusProjectionCheck {
    static func main() {
        mapsTranslationStatusIntoRenderState()
        mapsRewriteAndProcessingStatusesIntoRenderState()
        mapsFailureStatusesIntoRenderState()
        mapsEmptyStatusIntoRenderState()
        preservesLegacyStatusTextForUnmigratedStates()
        treatsBlankStatusAsRecording()
        print("MainCapsuleLegacyStatusProjectionCheck passed")
    }

    private static func mapsTranslationStatusIntoRenderState() {
        let projection = MainCapsuleLegacyStatusProjection(statusText: "翻译中")
        precondition(projection.phase == .translating)
        precondition(projection.statusTextOverride == "翻译中")

        let render = MainCapsuleRenderState(
            state: MainCapsuleState(phase: projection.phase),
            contentText: "",
            motion: MainCapsuleTextMotion(),
            statusTextOverride: projection.statusTextOverride
        )

        precondition(render.status == .processing)
        precondition(render.statusText == "翻译中")
    }

    private static func mapsRewriteAndProcessingStatusesIntoRenderState() {
        let cases: [(String, MainCapsulePhase, MainCapsuleRenderStatus)] = [
            ("整理中", .rewriting, .processing),
            ("检测中", .detectingSpeech, .processing),
            ("识别中", .recognizing, .processing),
            ("正在收尾", .longFormFinishing(message: "正在收尾"), .processing),
            ("自动结束", .autoFinished(message: "自动结束"), .processing),
        ]

        for item in cases {
            let projection = MainCapsuleLegacyStatusProjection(statusText: item.0)
            precondition(projection.phase == item.1)
            precondition(projection.statusTextOverride == item.0)

            let render = MainCapsuleRenderState(
                state: MainCapsuleState(phase: projection.phase),
                contentText: "",
                motion: MainCapsuleTextMotion(),
                statusTextOverride: projection.statusTextOverride
            )

            precondition(render.status == item.2)
            precondition(render.statusText == item.0)
        }
    }

    private static func mapsFailureStatusesIntoRenderState() {
        for text in ["录音失败", "保存失败", "识别失败"] {
            let projection = MainCapsuleLegacyStatusProjection(statusText: text)
            precondition(projection.phase == .failed(message: text))
            precondition(projection.statusTextOverride == text)

            let render = MainCapsuleRenderState(
                state: MainCapsuleState(phase: projection.phase),
                contentText: "",
                motion: MainCapsuleTextMotion(),
                statusTextOverride: projection.statusTextOverride
            )

            precondition(render.status == .failure)
            precondition(render.statusText == text)
        }
    }

    private static func mapsEmptyStatusIntoRenderState() {
        let projection = MainCapsuleLegacyStatusProjection(statusText: "无输入已停止")
        precondition(projection.phase == .empty(reason: "无输入已停止"))
        precondition(projection.statusTextOverride == "无输入已停止")

        let render = MainCapsuleRenderState(
            state: MainCapsuleState(phase: projection.phase),
            contentText: "",
            motion: MainCapsuleTextMotion(),
            statusTextOverride: projection.statusTextOverride
        )

        precondition(render.status == .empty)
        precondition(render.statusText == "无输入已停止")
    }

    private static func preservesLegacyStatusTextForUnmigratedStates() {
        let projection = MainCapsuleLegacyStatusProjection(statusText: "未迁移状态")
        precondition(projection.phase == .recording(instructions: nil))
        precondition(projection.statusTextOverride == "未迁移状态")

        let render = MainCapsuleRenderState(
            state: MainCapsuleState(phase: projection.phase),
            contentText: "",
            motion: MainCapsuleTextMotion(),
            statusTextOverride: projection.statusTextOverride
        )

        precondition(render.statusText == "未迁移状态")
    }

    private static func treatsBlankStatusAsRecording() {
        let projection = MainCapsuleLegacyStatusProjection(statusText: "  ")
        precondition(projection.phase == .recording(instructions: nil))
        precondition(projection.statusTextOverride == nil)
    }
}
