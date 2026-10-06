import Foundation

@main
struct RealtimeRecognitionHallucinationFilterCheck {
    static func main() {
        let filter = RealtimeRecognitionHallucinationFilter()

        precondition(filter.evaluate(
            text: "我。",
            previousPreviewText: "今天我们讨论功能优化。",
            authority: .fast
        ) == .suppress(reason: .silencePhrase))
        precondition(filter.evaluate(
            text: "我想。",
            previousPreviewText: "",
            authority: .fast
        ) == .suppress(reason: .silencePhrase))
        precondition(filter.evaluate(
            text: "Yeah",
            previousPreviewText: "",
            authority: .fast
        ) == .suppress(reason: .latinSilencePhrase))
        precondition(filter.evaluate(
            text: "I.",
            previousPreviewText: "已经有正常内容。",
            authority: .stopTail
        ) == .suppress(reason: .latinSilencePhrase))

        precondition(filter.evaluate(
            text: "我想修改这个功能。",
            previousPreviewText: "",
            authority: .fast
        ) == .keep("我想修改这个功能。"))
        precondition(filter.evaluate(
            text: "Yeah，我们继续测试。",
            previousPreviewText: "",
            authority: .fast
        ) == .keep("Yeah，我们继续测试。"))
        precondition(filter.evaluate(
            text: "最后由我。",
            previousPreviewText: "今天讨论分工。",
            authority: .correction
        ) == .keep("最后由我。"))

        let genuineShortFilter = RealtimeRecognitionHallucinationFilter()
        precondition(genuineShortFilter.evaluate(
            text: "结束。",
            previousPreviewText: "",
            authority: .fast
        ) == .keep("结束。"), "a genuine two-character tail must be delivered on its first result")

        print("RealtimeRecognitionHallucinationFilterCheck passed")
    }
}
