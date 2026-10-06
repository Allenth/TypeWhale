import Foundation

@main
struct PreviewTranscriptReducerCheck {
    static func main() {
        let sessionID = UUID()
        let planner = BoundaryCenteredPreviewPlanner()

        precondition(planner.proposeBoundary(
            sessionID: sessionID,
            chunkID: 0,
            chunkStartedAt: 0,
            capturedAt: 9.9,
            voiceActive: false
        ) == nil)

        let vadBoundary = planner.proposeBoundary(
            sessionID: sessionID,
            chunkID: 0,
            chunkStartedAt: 0,
            capturedAt: 10.2,
            voiceActive: false
        )
        precondition(vadBoundary?.kind == .voicePause)
        precondition(vadBoundary?.time == 10.2)

        let hardBoundary = planner.proposeBoundary(
            sessionID: sessionID,
            chunkID: 1,
            chunkStartedAt: 10.2,
            capturedAt: 28.2,
            voiceActive: true
        )
        precondition(hardBoundary?.kind == .hardLimit)

        let regularWindow = planner.correctionWindow(
            around: PreviewBoundary(sessionID: sessionID, chunkID: 2, time: 20, kind: .hardLimit),
            sessionStart: 0,
            availableAudioEnd: 31.25,
            recovery: false
        )
        precondition(regularWindow?.audioRange == PreviewAudioRange(start: 8.75, end: 31.25))
        precondition(regularWindow?.containsBoundaryInCenterSafeRegion == true)

        let recoveryWindow = planner.correctionWindow(
            around: PreviewBoundary(sessionID: sessionID, chunkID: 2, time: 20, kind: .hardLimit),
            sessionStart: 0,
            availableAudioEnd: 31.25,
            recovery: true
        )
        precondition(recoveryWindow?.audioRange.duration == 22.5)

        let hardWindow1 = planner.correctionWindow(
            around: PreviewBoundary(sessionID: sessionID, chunkID: 3, time: 18, kind: .hardLimit),
            sessionStart: 0,
            availableAudioEnd: 29.25,
            recovery: false
        )!
        let hardWindow2 = planner.correctionWindow(
            around: PreviewBoundary(sessionID: sessionID, chunkID: 4, time: 36, kind: .hardLimit),
            sessionStart: 0,
            availableAudioEnd: 47.25,
            recovery: false
        )!
        precondition(hardWindow1.audioRange.end > hardWindow2.audioRange.start, "maximum-gap hard windows must still overlap")

        var reducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 7, visibleCharacterLimit: 20)
        let firstFast = result(
            sessionID: sessionID,
            epoch: 7,
            text: "今天我们讨论实时预览方案",
            tokens: ["今", "天", "我", "们", "讨", "论", "实", "时", "预", "览", "方", "案"]
        )
        let firstUpdate = reducer.apply(.fast(firstFast))
        precondition(firstUpdate?.displayText == firstFast.text)
        let firstRevision = reducer.state.displayRevision

        precondition(reducer.apply(.fast(firstFast)) == nil, "identical display text must not publish twice")
        precondition(reducer.state.displayRevision == firstRevision)

        let stale = result(
            sessionID: sessionID,
            epoch: 6,
            text: "旧会话结果",
            tokens: ["旧", "会", "话"]
        )
        precondition(reducer.apply(.fast(stale)) == nil)
        precondition(reducer.state.displayText == firstFast.text)

        let firstCorrection = result(
            sessionID: sessionID,
            epoch: 7,
            text: "今天我们讨论实时预览方案",
            tokens: firstFast.tokens,
            timestamps: stride(from: 0.0, to: 12.0, by: 1.0).map(Float.init)
        )
        _ = reducer.apply(.correction(firstCorrection))

        let secondCorrection = result(
            sessionID: sessionID,
            epoch: 7,
            text: "今天我们讨论实时预览架构",
            tokens: ["今", "天", "我", "们", "讨", "论", "实", "时", "预", "览", "架", "构"],
            timestamps: stride(from: 0.0, to: 12.0, by: 1.0).map(Float.init)
        )
        let corrected = reducer.apply(.correction(secondCorrection))
        precondition(corrected?.confirmedText == "今天我们讨论实时预览")
        precondition(corrected?.mutableTailText == "架构")
        precondition(corrected?.displayText == "今天我们讨论实时预览架构")

        let confirmedBeforeConflict = reducer.state.confirmedText
        let conflict = result(
            sessionID: sessionID,
            epoch: 7,
            text: "今天我们研究另一条路线",
            tokens: ["今", "天", "我", "们", "研", "究", "另", "一", "条", "路", "线"]
        )
        let conflictUpdate = reducer.apply(.correction(conflict))
        precondition(reducer.state.confirmedText == confirmedBeforeConflict, "confirmed prefix must be immutable")
        precondition(conflictUpdate?.recoveryRequested == true, "material conflict must request recovery")

        let longTail = String(repeating: "新", count: 40)
        _ = reducer.apply(.fast(result(sessionID: sessionID, epoch: 7, text: longTail, tokens: Array(repeating: "新", count: 40))))
        precondition(reducer.state.displayText.count <= 20, "capsule projection must remain bounded")

        var shiftedReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 9, visibleCharacterLimit: 40)
        let leftWindow = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 9,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: "甲乙丙丁戊己",
            tokens: ["甲", "乙", "丙", "丁", "戊", "己"],
            tokenTimestamps: [5, 7, 9, 11, 13, 14]
        )
        let rightWindow = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 9,
            requestID: UUID(),
            chunkID: 2,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 10, end: 25),
            text: "丁戊己庚辛",
            tokens: ["丁", "戊", "己", "庚", "辛"],
            tokenTimestamps: [1, 3, 4, 6, 8]
        )
        _ = shiftedReducer.apply(.correction(leftWindow))
        let shiftedUpdate = shiftedReducer.apply(.correction(rightWindow))
        precondition(shiftedUpdate?.confirmedText == "甲乙丙丁戊己", "overlapping windows must align on absolute audio time")
        precondition(shiftedUpdate?.mutableTailText == "庚辛")
        precondition(shiftedUpdate?.recoveryRequested == false)

        var boundaryLimitedReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 14, visibleCharacterLimit: 40)
        let boundaryLimitedLeft = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 14,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: "甲乙丙丁戊己",
            tokens: ["甲", "乙", "丙", "丁", "戊", "己"],
            tokenTimestamps: [5, 7, 9, 11, 13, 14],
            boundary: PreviewBoundary(sessionID: sessionID, chunkID: 0, time: 10, kind: .hardLimit)
        )
        let boundaryLimitedRight = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 14,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 10, end: 25),
            text: "丁戊己庚辛",
            tokens: ["丁", "戊", "己", "庚", "辛"],
            tokenTimestamps: [1, 3, 4, 6, 8],
            boundary: PreviewBoundary(sessionID: sessionID, chunkID: 1, time: 20, kind: .hardLimit)
        )
        _ = boundaryLimitedReducer.apply(.fast(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 14,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 0, end: 10),
            text: "甲乙丙",
            tokens: ["甲", "乙", "丙"],
            tokenTimestamps: nil
        )))
        _ = boundaryLimitedReducer.apply(.fast(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 14,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 10, end: 20),
            text: "丁戊己庚辛",
            tokens: ["丁", "戊", "己", "庚", "辛"],
            tokenTimestamps: nil
        )))
        _ = boundaryLimitedReducer.apply(.correction(boundaryLimitedLeft))
        _ = boundaryLimitedReducer.apply(.correction(boundaryLimitedRight))
        precondition(
            boundaryLimitedReducer.state.confirmedText == "甲乙丙",
            "overlap may validate the seam, but confirmation must stop at the previous real chunk boundary"
        )
        precondition(boundaryLimitedReducer.state.mutableTailText == "丁戊己庚辛")

        var tokenFallbackReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 10, visibleCharacterLimit: 40)
        let tokenLeft = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 10,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: "甲乙丙丁戊己",
            tokens: ["甲", "乙", "丙", "丁", "戊", "己"],
            tokenTimestamps: nil
        )
        let tokenRight = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 10,
            requestID: UUID(),
            chunkID: 2,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 10, end: 25),
            text: "丁戊己庚辛",
            tokens: ["丁", "戊", "己", "庚", "辛"],
            tokenTimestamps: nil
        )
        _ = tokenFallbackReducer.apply(.correction(tokenLeft))
        let tokenFallbackUpdate = tokenFallbackReducer.apply(.correction(tokenRight))
        precondition(tokenFallbackUpdate?.confirmedText == "甲乙丙丁戊己")
        precondition(tokenFallbackUpdate?.mutableTailText == "庚辛")
        precondition(tokenFallbackUpdate?.recoveryRequested == false)

        let invalidTimestampResult = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 10,
            requestID: UUID(),
            chunkID: 3,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 10, end: 25),
            text: "越界",
            tokens: ["越", "界"],
            tokenTimestamps: [1, 16]
        )
        precondition(invalidTimestampResult.validatedTokenTimestamps == nil)

        var weakOverlapReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 11)
        _ = weakOverlapReducer.apply(.correction(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 11,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: "我们讨论方案",
            tokens: ["我", "们", "讨", "论", "方", "案"],
            tokenTimestamps: nil
        )))
        let weakOverlap = weakOverlapReducer.apply(.correction(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 11,
            requestID: UUID(),
            chunkID: 2,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 12, end: 27),
            text: "案后来修改",
            tokens: ["案", "后", "来", "修", "改"],
            tokenTimestamps: nil
        )))
        precondition(weakOverlap?.recoveryRequested == true, "one repeated token is not enough to confirm a seam")

        let degraded = weakOverlapReducer.markRecoveryRequested()
        precondition(degraded.recoveryRequested)

        var correctionAnchorReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 12, visibleCharacterLimit: 80)
        _ = correctionAnchorReducer.apply(.fast(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 12,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 0, end: 10),
            text: "前文已经稳定",
            tokens: ["前", "文", "已", "经", "稳", "定"],
            tokenTimestamps: nil
        )))
        let firstBoundaryCorrection = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 12,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 0, end: 20),
            text: "前文已经稳定甲乙丙",
            tokens: ["前", "文", "已", "经", "稳", "定", "甲", "乙", "丙"],
            tokenTimestamps: nil
        )
        _ = correctionAnchorReducer.apply(.correction(firstBoundaryCorrection))
        let growingFastSnapshot = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 12,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 10, end: 21),
            text: "甲乙丙后来继续",
            tokens: ["甲", "乙", "丙", "后", "来", "继", "续"],
            tokenTimestamps: nil
        )
        let anchoredFastUpdate = correctionAnchorReducer.apply(.fast(growingFastSnapshot))
        precondition(
            anchoredFastUpdate?.displayText == "前文已经稳定甲乙丙后来继续",
            "a correction must not take ownership of the live fast projection"
        )

        var crossChunkFastReducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 13, visibleCharacterLimit: 80)
        let completedFirstChunk = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 13,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 0, end: 10),
            text: "第一分块已经完整",
            tokens: ["第", "一", "分", "块", "已", "经", "完", "整"],
            tokenTimestamps: nil
        )
        _ = crossChunkFastReducer.apply(.fast(completedFirstChunk))
        let nextChunk = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 13,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 10, end: 11),
            text: "第二分块继续",
            tokens: ["第", "二", "分", "块", "继", "续"],
            tokenTimestamps: nil
        )
        let crossChunkFastUpdate = crossChunkFastReducer.apply(.fast(nextChunk))
        precondition(
            crossChunkFastUpdate?.displayText == "第一分块已经完整第二分块继续",
            "advancing to a new fast chunk must retain the previous provisional chunk"
        )

        // 真实长录音故障：首块 fast 覆盖 0...18s，但首个居中 correction 只覆盖 7...29s。
        // correction 获得边界附近所有权时，0...7s 的开头仍然只能由 fast 持有，不能随整块清理而消失。
        var uncoveredPrefixReducer = PreviewTranscriptReducer(
            sessionID: sessionID,
            epoch: 15,
            visibleCharacterLimit: 80
        )
        _ = uncoveredPrefixReducer.apply(.fast(PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 15,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 0, end: 18),
            text: "开头保留边界甲乙",
            tokens: ["开", "头", "保", "留", "边", "界", "甲", "乙"],
            tokenTimestamps: nil
        )))
        let firstShiftedCorrection = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 15,
            requestID: UUID(),
            chunkID: 0,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 7, end: 29),
            text: "留边界甲乙第二段",
            tokens: ["留", "边", "界", "甲", "乙", "第", "二", "段"],
            tokenTimestamps: [0, 2, 4, 6, 10, 12, 14, 16],
            boundary: PreviewBoundary(sessionID: sessionID, chunkID: 0, time: 18, kind: .hardLimit)
        )
        let secondShiftedCorrection = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 15,
            requestID: UUID(),
            chunkID: 1,
            sourceLane: .correction,
            audioRange: PreviewAudioRange(start: 18, end: 40),
            text: "第二段继续",
            tokens: ["第", "二", "段", "继", "续"],
            tokenTimestamps: [1, 3, 5, 7, 9],
            boundary: PreviewBoundary(sessionID: sessionID, chunkID: 1, time: 30, kind: .hardLimit)
        )
        _ = uncoveredPrefixReducer.apply(.correction(firstShiftedCorrection))
        _ = uncoveredPrefixReducer.apply(.correction(secondShiftedCorrection))
        let ownershipTransition = uncoveredPrefixReducer.lastOwnershipTransition
        let preservedPrefix = uncoveredPrefixReducer.state.confirmedText
            + uncoveredPrefixReducer.state.mutableTailText
        precondition(
            preservedPrefix == "开头保留边界甲乙第二段继续",
            "correction may replace only its covered audio range; the uncovered fast prefix must survive exactly once"
        )
        precondition(
            uncoveredPrefixReducer.state.recoveryRequested == true,
            "estimated fast timing must remain observable as a recovery state"
        )
        precondition(ownershipTransition?.decision == .correctionMerged)
        precondition(ownershipTransition?.replacementRange == secondShiftedCorrection.audioRange)
        precondition(ownershipTransition?.confirmedThroughTime != nil)
        precondition(
            ownershipTransition?.promotedFastCharacterCount == 3,
            "the trace must report the three fast-only prefix characters promoted before correction ownership"
        )

        print("PreviewTranscriptReducerCheck passed")
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
            sourceLane: .fast,
            audioRange: PreviewAudioRange(start: 0, end: 15),
            text: text,
            tokens: tokens,
            tokenTimestamps: timestamps
        )
    }
}
