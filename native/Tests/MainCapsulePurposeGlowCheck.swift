import Foundation

@main
struct MainCapsulePurposeGlowCheck {
    static func main() {
        verifiesIdeaPillGlowProjection()
        verifiesDictationHasNoPurposeGlow()
        verifiesOpenClawGlowProjectionIsPreserved()
        print("MainCapsulePurposeGlowCheck passed")
    }

    private static func verifiesIdeaPillGlowProjection() {
        let render = MainCapsuleRenderState(
            state: MainCapsuleState(
                phase: .recording(instructions: nil),
                purpose: .ideaPill
            ),
            contentText: "",
            motion: MainCapsuleTextMotion()
        )
        precondition(render.purposeGlow == .ideaPill)
    }

    private static func verifiesDictationHasNoPurposeGlow() {
        let render = MainCapsuleRenderState(
            state: MainCapsuleState(
                phase: .recording(instructions: nil),
                purpose: .dictation
            ),
            contentText: "",
            motion: MainCapsuleTextMotion()
        )
        precondition(render.purposeGlow == nil)
    }

    private static func verifiesOpenClawGlowProjectionIsPreserved() {
        let render = MainCapsuleRenderState(
            state: MainCapsuleState(
                phase: .recording(instructions: nil),
                purpose: .openClaw(connection: .connected)
            ),
            contentText: "",
            motion: MainCapsuleTextMotion()
        )
        precondition(render.purposeGlow == .openClaw)
    }
}
