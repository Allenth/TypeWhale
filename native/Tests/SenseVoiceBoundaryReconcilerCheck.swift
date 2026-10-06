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

var reconciler = SenseVoiceBoundaryReconciler(strategy: .audioTime)
let first = reconciler.consume(recognition(
    text: "今天讨论",
    tokens: ["今", "天", "讨", "论"],
    timestamps: [0.5, 1, 2, 3],
    start: 0,
    end: 4
))
precondition(first.newlyConfirmedText.isEmpty)
precondition(first.volatileTailText == "今天讨论")

// 文字可以完全改写；只要音频时间重叠，稳定边界就按时间推进。
let aligned = reconciler.consume(recognition(
    text: "我们研究云端识别",
    tokens: ["我", "们", "研", "究", "云", "端", "识", "别"],
    timestamps: nil,
    start: 2,
    end: 6
))
precondition(!aligned.newlyConfirmedText.isEmpty)
precondition(aligned.confirmedText == aligned.newlyConfirmedText)
precondition(!aligned.volatileTailText.isEmpty)
precondition(aligned.confirmedThroughTime == 3)
precondition(!aligned.recoveryRequired)

// 后续重叠窗口继续按时间追加，不依赖词面 suffix/prefix。
let fallback = reconciler.consume(recognition(
    text: "在线模型支持流式输出",
    tokens: ["在", "线", "模", "型", "支", "持", "流", "式", "输", "出"],
    timestamps: nil,
    start: 4,
    end: 8
))
precondition(fallback.confirmedText.hasPrefix("今天讨论"))
precondition(!fallback.newlyConfirmedText.isEmpty)
precondition(!fallback.volatileTailText.isEmpty)
precondition(!fallback.recoveryRequired)

// 真实向前缺口只是诊断：先确认旧尾，再保留新窗口，不丢上下文。
let beforeFailure = fallback.confirmedText
let failed = reconciler.consume(recognition(
    text: "完全不相关",
    tokens: ["完", "全", "不", "相", "关"],
    timestamps: nil,
    start: 8,
    end: 10
))
precondition(failed.confirmedText.hasPrefix(beforeFailure))
precondition(!failed.newlyConfirmedText.isEmpty)
precondition(failed.volatileTailText == "完全不相关")
precondition(failed.recoveryRequired)

print("SenseVoiceBoundaryReconcilerCheck passed")
