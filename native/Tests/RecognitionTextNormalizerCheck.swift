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

        precondition(isMeaningfulRecognitionText("我", hasPriorPreview: true))
    }
}
