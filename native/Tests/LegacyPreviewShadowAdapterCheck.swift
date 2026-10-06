import Foundation

enum RecognitionLanguageMode {
    case chinese

    static func load() -> RecognitionLanguageMode {
        .chinese
    }
}

@main
struct LegacyPreviewShadowAdapterCheck {
    static func main() {
        let currentID = TranscriptionSessionID(rawValue: UUID())
        var adapter = LegacyPreviewShadowAdapter(sessionID: currentID, providerEpoch: 1)
        var reducer = TranscriptReducer(sessionID: currentID, providerEpoch: 1)

        reduce(adapter.consume(snapshot(
            revision: 1,
            stableCount: 0,
            stable: "",
            volatile: "今天讨论在线模型"
        )), with: &reducer)
        precondition(reducer.state.confirmedText.isEmpty)
        precondition(reducer.state.volatileText == "今天讨论在线模型")
        let firstPartialRevision = reducer.state.volatileRevision

        // 同一内容只推进 stable 边界时，应晋升已确认内容，不发生清空或重复。
        reduce(adapter.consume(snapshot(
            revision: 2,
            stableCount: 4,
            stable: "今天讨论",
            volatile: "在线模型"
        )), with: &reducer)
        precondition(reducer.state.confirmedText == "今天讨论")
        precondition(reducer.state.volatileText == "在线模型")
        precondition(reducer.state.confirmedText + reducer.state.volatileText == "今天讨论在线模型")

        // volatile 允许整体替换，但 revision 必须递增。
        reduce(adapter.consume(snapshot(
            revision: 3,
            stableCount: 4,
            stable: "今天讨论",
            volatile: "在线模型支持流式输出"
        )), with: &reducer)
        precondition(reducer.state.volatileText == "在线模型支持流式输出")
        precondition(reducer.state.volatileRevision > firstPartialRevision)

        // stable 计数倒退是可恢复诊断；不得改写已有文本状态。
        let beforeRegressionText = reducer.state.confirmedText + reducer.state.volatileText
        let regressionEvents = adapter.consume(snapshot(
            revision: 5,
            stableCount: 2,
            stable: "今天",
            volatile: "错误回退"
        ))
        precondition(regressionEvents.count == 1)
        if case .failed(_, let failure) = regressionEvents[0] {
            precondition(failure.code == .internalInvariant)
            precondition(failure.isRecoverable)
        } else {
            preconditionFailure("stable regression must emit a failure diagnostic")
        }
        reduce(regressionEvents, with: &reducer)
        precondition(reducer.state.confirmedText + reducer.state.volatileText == beforeRegressionText)

        // complete 幂等，只产生一次终态事件。
        let completion = adapter.complete()
        precondition(completion.count == 1)
        precondition(adapter.complete().isEmpty)
        reduce(completion, with: &reducer)
        precondition(reducer.state.lifecycle == .completed)

        // 候选产品流必须能消费生产预览的长文本快照；不能被旧胶囊 160 字窗口截断。
        let candidateID = TranscriptionSessionID(rawValue: UUID())
        var candidateAdapter = LegacyPreviewShadowAdapter(sessionID: candidateID, providerEpoch: 1)
        var candidateReducer = TranscriptReducer(sessionID: candidateID, providerEpoch: 1)
        let longStable = String(repeating: "长", count: 220)
        let longVolatile = String(repeating: "尾", count: 40)
        reduce(candidateAdapter.consume(snapshot(
            revision: 1,
            stableCount: longStable.count,
            stable: longStable,
            volatile: longVolatile
        )), with: &candidateReducer)
        precondition(candidateReducer.state.confirmedText == longStable)
        precondition(candidateReducer.state.volatileText == longVolatile)

        let candidateProjection = PreviewStateProjector.project(
            candidateReducer.state,
            visibleCharacterLimit: ShadowTranscriptionRuntime.candidateVisibleCharacterLimit
        )
        precondition(candidateProjection.displayText == longStable + longVolatile)

        // 旧录音适配器产生的事件必须被当前 session reducer 拒绝。
        let oldID = TranscriptionSessionID(rawValue: UUID())
        var oldAdapter = LegacyPreviewShadowAdapter(sessionID: oldID, providerEpoch: 1)
        let stateBeforeOldEvent = reducer.state
        let oldEvents = oldAdapter.consume(snapshot(
            revision: 1,
            stableCount: 0,
            stable: "",
            volatile: "上一轮晚到文本"
        ))
        for event in oldEvents {
            precondition(reducer.apply(event) == nil)
        }
        precondition(reducer.state == stateBeforeOldEvent)

        print("LegacyPreviewShadowAdapterCheck passed")
    }

    private static func snapshot(
        revision: Int,
        stableCount: Int,
        stable: String,
        volatile: String
    ) -> PreviewDisplaySnapshot {
        PreviewDisplaySnapshot(
            revision: revision,
            stableCharacterCount: stableCount,
            stableWindowText: stable,
            volatileTailText: volatile
        )
    }

    private static func reduce(
        _ events: [TranscriptionEvent],
        with reducer: inout TranscriptReducer
    ) {
        for event in events {
            _ = reducer.apply(event)
        }
    }
}
