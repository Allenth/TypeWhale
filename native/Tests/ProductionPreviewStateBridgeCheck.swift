import Foundation

@main
struct ProductionPreviewStateBridgeCheck {
    static func main() async {
        await publishesSnapshotAsPreviewViewState()
        await incrementsSequenceMonotonically()
        await completesAndStopsAcceptingSnapshots()
        print("ProductionPreviewStateBridgeCheck passed")
    }

    private static func publishesSnapshotAsPreviewViewState() async {
        let bridge = ProductionPreviewStateBridge()
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let stream = bridge.begin(sessionID: sessionID)
        bridge.consume(PreviewDisplaySnapshot(
            revision: 7,
            stableCharacterCount: 4,
            stableWindowText: "用户体验",
            volatileTailText: "不要了吗"
        ))

        guard let state = await firstValue(from: stream) else {
            preconditionFailure("bridge must publish a state after consuming a snapshot")
        }
        precondition(state.sessionID == sessionID)
        precondition(state.providerEpoch == 1)
        precondition(state.sequence == 1)
        precondition(state.stableCharacterCount == 4)
        precondition(state.stableWindowText == "用户体验")
        precondition(state.volatileTailText == "不要了吗")
        precondition(state.displayText == "用户体验不要了吗")
        precondition(state.lifecycle == .running)
        precondition(state.failure == nil)
    }

    private static func incrementsSequenceMonotonically() async {
        let bridge = ProductionPreviewStateBridge()
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let stream = bridge.begin(sessionID: sessionID)
        bridge.consume(PreviewDisplaySnapshot(
            revision: 1,
            stableCharacterCount: 1,
            stableWindowText: "甲",
            volatileTailText: ""
        ))
        bridge.consume(PreviewDisplaySnapshot(
            revision: 2,
            stableCharacterCount: 2,
            stableWindowText: "甲乙",
            volatileTailText: "丙"
        ))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        precondition(first?.sequence == 1)
        precondition(second?.sequence == 2)
        precondition(second?.displayText == "甲乙丙")
    }

    private static func completesAndStopsAcceptingSnapshots() async {
        let bridge = ProductionPreviewStateBridge()
        let sessionID = TranscriptionSessionID(rawValue: UUID())
        let stream = bridge.begin(sessionID: sessionID)
        bridge.consume(PreviewDisplaySnapshot(
            revision: 1,
            stableCharacterCount: 2,
            stableWindowText: "完成",
            volatileTailText: "前"
        ))
        bridge.complete()
        bridge.consume(PreviewDisplaySnapshot(
            revision: 2,
            stableCharacterCount: 4,
            stableWindowText: "不应",
            volatileTailText: "继续"
        ))

        var iterator = stream.makeAsyncIterator()
        let running = await iterator.next()
        let terminal = await iterator.next()
        let afterTerminal = await iterator.next()
        precondition(running?.lifecycle == .running)
        precondition(terminal?.lifecycle == .completed)
        precondition(terminal?.displayText == "完成前")
        precondition(afterTerminal == nil, "bridge must finish after terminal state")
    }

    private static func firstValue(
        from stream: AsyncStream<PreviewViewState>
    ) async -> PreviewViewState? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}
