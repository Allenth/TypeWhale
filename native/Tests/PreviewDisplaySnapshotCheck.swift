import Foundation

@main
struct PreviewDisplaySnapshotCheck {
    static func main() {
        let sessionID = UUID()

        // 1. fast 事件：全部内容属于可变尾部，稳定区为空。
        var reducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 1, visibleCharacterLimit: 40)
        let fastUpdate = reducer.apply(.fast(result(
            sessionID: sessionID,
            epoch: 1,
            text: "今天我们讨论实时预览方案",
            tokens: ["今", "天", "我", "们", "讨", "论", "实", "时", "预", "览", "方", "案"]
        )))
        guard let fastSnapshot = fastUpdate?.displaySnapshot else {
            preconditionFailure("fast publish must carry a display snapshot")
        }
        precondition(fastSnapshot.stableCharacterCount == 0)
        precondition(fastSnapshot.stableWindowText.isEmpty)
        precondition(fastSnapshot.volatileTailText == "今天我们讨论实时预览方案")
        precondition(fastSnapshot.revision == fastUpdate?.displayRevision)
        precondition(fastSnapshot.displayText == fastUpdate?.displayText)

        // 2. 两次校正确认稳定前缀：稳定区只追加，尾部保持可变。
        _ = reducer.apply(.correction(result(
            sessionID: sessionID,
            epoch: 1,
            text: "今天我们讨论实时预览方案",
            tokens: ["今", "天", "我", "们", "讨", "论", "实", "时", "预", "览", "方", "案"],
            timestamps: stride(from: 0.0, to: 12.0, by: 1.0).map(Float.init)
        )))
        let confirmedUpdate = reducer.apply(.correction(result(
            sessionID: sessionID,
            epoch: 1,
            text: "今天我们讨论实时预览架构",
            tokens: ["今", "天", "我", "们", "讨", "论", "实", "时", "预", "览", "架", "构"],
            timestamps: stride(from: 0.0, to: 12.0, by: 1.0).map(Float.init)
        )))
        guard let confirmedSnapshot = confirmedUpdate?.displaySnapshot else {
            preconditionFailure("correction publish must carry a display snapshot")
        }
        precondition(confirmedSnapshot.stableCharacterCount == 10)
        precondition(confirmedSnapshot.stableWindowText == "今天我们讨论实时预览")
        precondition(confirmedSnapshot.volatileTailText == "架构")
        precondition(
            confirmedSnapshot.stableCharacterCount > fastSnapshot.stableCharacterCount
                || confirmedSnapshot.stableWindowText.hasPrefix(fastSnapshot.stableWindowText),
            "stable region must only grow"
        )

        // 3. 内容不变但确认边界前移：必须重新发布，让显示层更新稳定/可变分界。
        var boundaryReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 2, visibleCharacterLimit: 40)
        let sameTokens = ["甲", "乙", "丙", "丁", "戊", "己"]
        let sameTimestamps: [Float] = [0, 1, 2, 3, 4, 5]
        _ = boundaryReducer.apply(.correction(result(
            sessionID: sessionID,
            epoch: 2,
            text: "甲乙丙丁戊己",
            tokens: sameTokens,
            timestamps: sameTimestamps
        )))
        let textBefore = boundaryReducer.state.displayText
        let stableBefore = boundaryReducer.state.displaySnapshot?.stableCharacterCount ?? 0
        let boundaryOnlyUpdate = boundaryReducer.apply(.correction(result(
            sessionID: sessionID,
            epoch: 2,
            text: "甲乙丙丁戊己",
            tokens: sameTokens,
            timestamps: sameTimestamps
        )))
        guard let boundaryOnlySnapshot = boundaryOnlyUpdate?.displaySnapshot else {
            preconditionFailure("a pure boundary advance must still publish a snapshot")
        }
        precondition(boundaryOnlyUpdate?.displayText == textBefore, "boundary-only publish must not change content")
        precondition(
            boundaryOnlySnapshot.stableCharacterCount > stableBefore,
            "boundary-only publish must advance the stable boundary"
        )

        // 4. 有界窗口：尾部优先占用窗口，稳定窗口可被裁剪，总长不超过上限。
        var boundedReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 3, visibleCharacterLimit: 20)
        let longTail = String(repeating: "新", count: 40)
        let boundedUpdate = boundedReducer.apply(.fast(result(
            sessionID: sessionID,
            epoch: 3,
            text: longTail,
            tokens: Array(repeating: "新", count: 40)
        )))
        guard let boundedSnapshot = boundedUpdate?.displaySnapshot else {
            preconditionFailure("bounded publish must carry a display snapshot")
        }
        precondition(boundedSnapshot.displayText.count <= 20)
        precondition(boundedSnapshot.stableWindowText.isEmpty)
        precondition(boundedSnapshot.volatileTailText.count == 20)

        // 5. 长录音会话投影：稳定计数是全量确认字符数，窗口有界。
        var session = LongFormTranscriptionSession()
        session.appendConfirmed(PreviewTranscriptSegment(
            id: UUID(),
            text: "第一段确认文本",
            audioRange: PreviewAudioRange(start: 0, end: 10)
        ))
        session.appendConfirmed(PreviewTranscriptSegment(
            id: UUID(),
            text: "第二段确认文本",
            audioRange: PreviewAudioRange(start: 10, end: 20)
        ))
        let projected = session.capsuleProjectionSnapshot(mutableTail: "正在说的尾巴", revision: 7, limit: 10)
        precondition(projected.revision == 7)
        precondition(projected.stableCharacterCount == 14, "stable count must reflect ALL confirmed characters, not the visible window")
        precondition(projected.volatileTailText == "正在说的尾巴")
        precondition(projected.displayText.count <= 10)
        precondition(projected.stableWindowText == "确认文本", "stable window must be the most recent confirmed suffix")

        // 重复 append 同一 segment 不得重复计数。
        let duplicated = PreviewTranscriptSegment(
            id: UUID(),
            text: "重复段",
            audioRange: PreviewAudioRange(start: 20, end: 25)
        )
        session.appendConfirmed(duplicated)
        session.appendConfirmed(duplicated)
        let deduplicated = session.capsuleProjectionSnapshot(mutableTail: "", revision: 8, limit: 100)
        precondition(deduplicated.stableCharacterCount == 17, "duplicate segment ids must not inflate the stable count")

        print("PreviewDisplaySnapshotCheck passed")
    }

    private static func result(
        sessionID: UUID,
        epoch: Int,
        text: String,
        tokens: [String],
        timestamps: [Float]? = nil
    ) -> PreviewRecognitionResult {
        PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: epoch,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: text,
            tokens: tokens,
            tokenTimestamps: timestamps
        )
    }
}
