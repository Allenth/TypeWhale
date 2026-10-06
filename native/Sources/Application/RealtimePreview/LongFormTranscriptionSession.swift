import Foundation

struct LongFormTranscriptionSession: Sendable {
    let maxDuration: TimeInterval
    private(set) var confirmedSegments: [PreviewTranscriptSegment] = []
    /// 全量确认字符数（跨全部片段），供展示快照表达单调递增的稳定边界。
    private(set) var confirmedCharacterTotal = 0

    let usesPauseAutoFinish = false
    let usesNoTextTimeout = false

    init(maxDuration: TimeInterval = 4 * 60 * 60) {
        self.maxDuration = maxDuration
    }

    mutating func appendConfirmed(_ segment: PreviewTranscriptSegment) {
        guard !confirmedSegments.contains(where: { $0.id == segment.id }) else { return }
        confirmedSegments.append(segment)
        confirmedCharacterTotal += segment.text.count
    }

    func shouldFinish(elapsed: TimeInterval) -> Bool {
        elapsed >= maxDuration
    }

    func capsuleProjection(mutableTail: String, limit: Int = 160) -> String {
        let recentConfirmed = confirmedSegments.suffix(4).map(\.text).joined()
        return String((recentConfirmed + mutableTail).suffix(max(1, limit)))
    }

    /// 展示快照版投影：尾部优先占用窗口，稳定窗口从最近确认片段回填；
    /// `stableCharacterCount` 始终是全量确认字符数，不受可见窗口裁剪影响。
    func capsuleProjectionSnapshot(mutableTail: String, revision: Int, limit: Int = 160) -> PreviewDisplaySnapshot {
        let cappedLimit = max(1, limit)
        let volatileVisible = String(mutableTail.suffix(cappedLimit))
        var remaining = cappedLimit - volatileVisible.count
        var recentConfirmed = ""
        for segment in confirmedSegments.reversed() where remaining > 0 {
            let suffix = String(segment.text.suffix(remaining))
            recentConfirmed = suffix + recentConfirmed
            remaining -= suffix.count
        }
        return PreviewDisplaySnapshot(
            revision: revision,
            stableCharacterCount: confirmedCharacterTotal,
            stableWindowText: recentConfirmed,
            volatileTailText: volatileVisible
        )
    }

    func assembleFinalTranscript(mutableTail: String) -> String {
        confirmedSegments.map(\.text).joined() + mutableTail
    }
}
