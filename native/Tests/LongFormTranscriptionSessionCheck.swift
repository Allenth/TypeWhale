import Foundation

@main
struct LongFormTranscriptionSessionCheck {
    static func main() {
        var session = LongFormTranscriptionSession(maxDuration: 4 * 60 * 60)
        precondition(!session.shouldFinish(elapsed: 65 * 60))
        precondition(session.shouldFinish(elapsed: 4 * 60 * 60))
        precondition(!session.usesPauseAutoFinish)
        precondition(!session.usesNoTextTimeout)

        for minute in 0..<65 {
            session.appendConfirmed(PreviewTranscriptSegment(
                id: UUID(),
                text: "第\(minute)分钟。",
                audioRange: PreviewAudioRange(start: Double(minute * 60), end: Double((minute + 1) * 60))
            ))
        }
        precondition(session.confirmedSegments.count == 65)
        precondition(session.capsuleProjection(mutableTail: "当前尾部", limit: 30).count <= 30)
        let final = session.assembleFinalTranscript(mutableTail: "当前尾部")
        precondition(final.hasPrefix("第0分钟。"))
        precondition(final.hasSuffix("当前尾部"))

        print("LongFormTranscriptionSessionCheck passed")
    }
}
