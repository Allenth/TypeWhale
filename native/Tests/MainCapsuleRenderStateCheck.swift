import Foundation

@main
struct MainCapsuleRenderStateCheck {
    static func main() {
        rendersVisibleTextFromStateAndMotion()
        mapsProcessingPhasesToStatusText()
        clampsVisibleCountsToContentLength()
        preservesPurposeContextAndIndicators()
        carriesWaveformBandsForDrawing()
        mapsHiddenAndFailureStates()
        print("MainCapsuleRenderStateCheck passed")
    }

    private static func rendersVisibleTextFromStateAndMotion() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 4, stableCharacterCount: 2)
        _ = motion.advance()

        let render = MainCapsuleRenderState(
            state: .recording(instructions: "再次按下 Fn 完成录音"),
            contentText: "我要测试",
            motion: motion
        )

        precondition(render.status == .recording)
        precondition(render.statusText == "录音中")
        precondition(render.targetText == "我要测试")
        precondition(render.displayedText == "我要")
        precondition(render.visibleCharacterCount == 2)
        precondition(render.visibleStableCharacterCount == 2)
        precondition(render.needsTextTimer)
    }

    private static func mapsProcessingPhasesToStatusText() {
        let cases: [(MainCapsulePhase, MainCapsuleRenderStatus, String)] = [
            (.detectingSpeech, .processing, "检测中"),
            (.recognizing, .processing, "识别中"),
            (.rewriting, .processing, "整理中"),
            (.translating, .processing, "翻译中"),
            (.longFormFinishing(message: "请稍候..."), .processing, "正在收尾"),
            (.autoFinished(message: "正在识别"), .processing, "自动结束"),
            (.empty(reason: "未检测到人声"), .empty, "无输入已停止")
        ]

        for item in cases {
            let render = MainCapsuleRenderState(
                state: MainCapsuleState(phase: item.0),
                contentText: "",
                motion: MainCapsuleTextMotion()
            )
            precondition(render.status == item.1)
            precondition(render.statusText == item.2)
        }
    }

    private static func clampsVisibleCountsToContentLength() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 30, stableCharacterCount: 20)

        let render = MainCapsuleRenderState(
            state: MainCapsuleState(phase: .recording(instructions: nil)),
            contentText: "短句",
            motion: motion
        )

        precondition(render.targetText == "短句")
        precondition(render.displayedText == "短句")
        precondition(render.visibleCharacterCount == 2)
        precondition(render.visibleStableCharacterCount == 2)
    }

    private static func preservesPurposeContextAndIndicators() {
        var motion = MainCapsuleTextMotion()
        _ = motion.apply(targetCharacterCount: 3, stableCharacterCount: 1)

        let state = MainCapsuleState(
            phase: .recording(instructions: nil),
            purpose: .openClaw(connection: .connected),
            context: MainCapsuleContext(targetAppName: "ChatGPT", modeName: "OpenClaw", autoTranslateEnabled: true),
            indicators: MainCapsuleIndicators(remainingSeconds: 12, memoryHigh: true)
        )
        let render = MainCapsuleRenderState(
            state: state,
            contentText: "测试中",
            motion: motion
        )

        precondition(render.purpose == .openClaw(connection: .connected))
        precondition(render.context.targetAppName == "ChatGPT")
        precondition(render.context.modeName == "OpenClaw")
        precondition(render.context.autoTranslateEnabled)
        precondition(render.indicators.remainingSeconds == 12)
        precondition(render.indicators.memoryHigh)
    }

    private static func carriesWaveformBandsForDrawing() {
        var waveform = MainCapsuleWaveformMotion()
        waveform.apply([1.0, 0.5])

        let render = MainCapsuleRenderState(
            state: MainCapsuleState(phase: .recording(instructions: nil)),
            contentText: "",
            motion: MainCapsuleTextMotion(),
            waveform: waveform
        )

        precondition(render.waveformBands.count == 7)
        precondition(render.waveformBands[0] > 0.5)
        precondition(render.waveformBands[1] > 0.2)
    }

    private static func mapsHiddenAndFailureStates() {
        let hidden = MainCapsuleRenderState(
            state: MainCapsuleState(phase: .hidden),
            contentText: "不会显示",
            motion: MainCapsuleTextMotion()
        )
        precondition(hidden.status == .hidden)
        precondition(hidden.isHidden)

        let failed = MainCapsuleRenderState(
            state: MainCapsuleState(phase: .failed(message: "识别失败")),
            contentText: "",
            motion: MainCapsuleTextMotion()
        )
        precondition(failed.status == .failure)
        precondition(failed.statusText == "识别失败")
    }
}
