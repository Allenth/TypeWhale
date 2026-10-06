import Foundation

private func recognition(
    text: String,
    tokens: [String],
    timestamps: [Float]? = nil,
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

private func checkConflictingBoundaryDoesNotBecomeStable() {
    var reconciler = SenseVoiceBoundaryReconciler()
    _ = reconciler.consume(recognition(
        text: "今天我们讨论公司",
        tokens: ["今", "天", "我", "们", "讨", "论", "公", "司"],
        start: 0,
        end: 6
    ))

    let result = reconciler.consume(recognition(
        text: "功功能优化",
        tokens: ["功", "功", "能", "优", "化"],
        start: 4,
        end: 8
    ))

    let composed = result.confirmedText + result.volatileTailText
    precondition(!composed.contains("公司功功能"), "conflicting seam must not be hard-stitched into stable text")
    precondition(result.recoveryRequired, "conflicting content overlap must request recovery instead of trusting time overlap")
    precondition(result.seamConfidence == .noOverlapRecoveryTriggered)
}

private func checkCompanyCanBoundaryDoesNotBecomeStable() {
    var reconciler = SenseVoiceBoundaryReconciler()
    _ = reconciler.consume(recognition(
        text: "今天我们讨论公司能",
        tokens: ["今", "天", "我", "们", "讨", "论", "公", "司", "能"],
        start: 0,
        end: 6
    ))

    let result = reconciler.consume(recognition(
        text: "功功能可以优化",
        tokens: ["功", "功", "能", "可", "以", "优", "化"],
        start: 4,
        end: 8
    ))

    let composed = result.confirmedText + result.volatileTailText
    precondition(!composed.contains("公司能功功能"), "conflicting company/function seam must not become stable text")
    precondition(result.recoveryRequired, "company/function seam conflict must request recovery")
    precondition(result.seamConfidence == .noOverlapRecoveryTriggered)
}

private func checkVerifiedOverlapCanAdvanceStablePrefix() {
    var reconciler = SenseVoiceBoundaryReconciler()
    _ = reconciler.consume(recognition(
        text: "今天我们讨论功能",
        tokens: ["今", "天", "我", "们", "讨", "论", "功", "能"],
        start: 0,
        end: 6
    ))

    let result = reconciler.consume(recognition(
        text: "功能优化",
        tokens: ["功", "能", "优", "化"],
        start: 4,
        end: 8
    ))

    precondition(result.confirmedText == "今天我们讨论功能")
    precondition(result.newlyConfirmedText == "今天我们讨论功能")
    precondition(result.volatileTailText == "优化")
    precondition(!result.recoveryRequired)
    precondition(result.seamConfidence == .tokenVerified)
}

@main
struct SenseVoiceContentSeamVerificationCheck {
    static func main() {
        checkConflictingBoundaryDoesNotBecomeStable()
        checkCompanyCanBoundaryDoesNotBecomeStable()
        checkVerifiedOverlapCanAdvanceStablePrefix()
        print("SenseVoiceContentSeamVerificationCheck passed")
    }
}
