import Foundation

@main
struct RecognitionTextNormalizerCheck {
    static func main() {
        precondition(!isMeaningfulRecognitionText(""))
        precondition(!isMeaningfulRecognitionText("。"))
        precondition(!isMeaningfulRecognitionText("."))
        precondition(!isMeaningfulRecognitionText("我"))
        precondition(!isMeaningfulRecognitionText("我。"))
        precondition(!isMeaningfulRecognitionText("嗯"))

        precondition(isMeaningfulRecognitionText("好的"))
        precondition(isMeaningfulRecognitionText("打开设置"))
        precondition(isMeaningfulRecognitionText("我想修改这个功能"))
        precondition(cleanRecognitionText("，目前的这些功能的话都是同行玩剩下的。") == "目前的这些功能的话都是同行玩剩下的。")
        precondition(cleanRecognitionText("...hello") == "hello")
        precondition(cleanRecognitionText(". lo.. 跳跃了。。是了。lo. 去了。了。") == "跳跃了。。是了。lo. 去了。了。")

        precondition(isMeaningfulRecognitionText("我", hasPriorPreview: true))

        precondition(isMeaningfulRealtimePreviewText("我想修改这个功能", previousPreview: ""))
        precondition(isMeaningfulRealtimePreviewText("我想修改这个功能的按钮", previousPreview: "我想修改这个功能"))
        precondition(!isMeaningfulRealtimePreviewText("我", previousPreview: "我想修改这个功能"))
        precondition(!isMeaningfulRealtimePreviewText("词。。", previousPreview: "我想修改这个功能"))
        precondition(!isMeaningfulRealtimePreviewText("出来很多。", previousPreview: "候蹦出来很多单个的字"))
        precondition(!isMeaningfulRealtimePreviewText("我想修改这个功能。。。。", previousPreview: "我想修改这个功能"))
        precondition(!isMeaningfulRealtimePreviewText("lo.. 跳跃了。。是了。lo. 去了。了。", previousPreview: ""))
    }
}
