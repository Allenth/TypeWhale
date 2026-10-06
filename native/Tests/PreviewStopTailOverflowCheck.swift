import Foundation

@main
struct PreviewStopTailOverflowCheck {
    static func main() {
        let sessionID = UUID()
        var reducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 1)
        let stopTail = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 1,
            requestID: UUID(),
            chunkID: .max,
            sourceLane: .stopTail,
            audioRange: PreviewAudioRange(start: 100, end: 122.5),
            text: "停止尾部文本",
            tokens: ["停", "止", "尾", "部", "文", "本"],
            tokenTimestamps: nil
        )

        let update = reducer.apply(.correction(stopTail))
        precondition(update?.mutableTailText == "停止尾部文本")
        print("PreviewStopTailOverflowCheck passed")
    }
}
