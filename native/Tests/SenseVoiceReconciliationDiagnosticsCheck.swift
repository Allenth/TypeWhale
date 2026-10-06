import Foundation

private func recognition(
    text: String,
    tokens: [String],
    timestamps: [Float]?,
    start: TimeInterval,
    end: TimeInterval
) -> SenseVoiceSnapshotRecognition {
    SenseVoiceSnapshotRecognition(
        text: text,
        tokens: tokens,
        tokenTimestamps: timestamps,
        audioRange: TranscriptionAudioRange(start: start, end: end)
    )
}

private func checkTimeOverlapOnlySeam() {
    var reconciler = SenseVoiceBoundaryReconciler(strategy: .audioTime)
    _ = reconciler.consume(recognition(
        text: "今天讨论",
        tokens: ["今", "天", "讨", "论"],
        timestamps: [0.5, 1, 2, 3],
        start: 0,
        end: 4
    ))
    let result = reconciler.consume(recognition(
        text: "完全不同",
        tokens: ["完", "全", "不", "同"],
        timestamps: [0.5, 1, 2, 3],
        start: 2,
        end: 6
    ))
    precondition(result.seamConfidence == .timeOverlapOnly)
}

private func checkTokenVerifiedSeam() {
    var reconciler = SenseVoiceBoundaryReconciler(strategy: .lexicalOverlap)
    _ = reconciler.consume(recognition(
        text: "今天讨论功能",
        tokens: ["今", "天", "讨", "论", "功", "能"],
        timestamps: [0.2, 0.5, 1.0, 1.4, 2.0, 2.4],
        start: 0,
        end: 4
    ))
    let result = reconciler.consume(recognition(
        text: "讨论功能优化",
        tokens: ["讨", "论", "功", "能", "优", "化"],
        timestamps: [0.0, 0.4, 1.0, 1.4, 2.0, 2.4],
        start: 1,
        end: 5
    ))
    precondition(result.seamConfidence == .tokenVerified)
}

private func checkRecoverySeam() {
    var reconciler = SenseVoiceBoundaryReconciler(strategy: .lexicalOverlap)
    _ = reconciler.consume(recognition(
        text: "今天讨论公司",
        tokens: ["今", "天", "讨", "论", "公", "司"],
        timestamps: [0.2, 0.5, 1.0, 1.4, 2.0, 2.4],
        start: 0,
        end: 4
    ))
    let result = reconciler.consume(recognition(
        text: "功功能优化",
        tokens: ["功", "功", "能", "优", "化"],
        timestamps: [0.0, 0.4, 0.8, 1.3, 1.8],
        start: 2,
        end: 6
    ))
    precondition(result.recoveryRequired)
    precondition(result.seamConfidence == .noOverlapRecoveryTriggered)
}

checkTimeOverlapOnlySeam()
checkTokenVerifiedSeam()
checkRecoverySeam()
print("SenseVoiceReconciliationDiagnosticsCheck passed")
