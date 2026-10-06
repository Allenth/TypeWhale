import Foundation

enum CapsuleTextBufferUpdate {
    case reset
    case ignored
    case updated(fadeStartIndex: Int?, needsDraftTimer: Bool, shouldStopDraftTimer: Bool)
}

enum CapsuleTextBufferAdvance {
    case finished
    case refreshedAndFinished
    case advanced(fadeStartIndex: Int?)
}

final class CapsuleTextBuffer {
    private let animatedTailLimit: Int
    private let firstPreviewMinimumCharacters: Int
    private(set) var targetDraft = ""
    private(set) var displayedDraft = ""
    private var realtimeRevisionCount = 0
    /// targetDraft 中稳定前缀的长度；其后为可变尾部，允许原位修订并以弱化样式显示。
    private(set) var stableTargetLength = 0
    /// 上一次快照的会话级稳定字符总数；用于检测“稳定区只追加”的增量与窗口左裁剪量。
    private var stableAnchorCount = 0

    /// displayedDraft 中可变尾部的起始下标；其之前的字符属于稳定区。
    var displayedVolatileStartIndex: Int {
        min(stableTargetLength, displayedDraft.count)
    }

    init(animatedTailLimit: Int, firstPreviewMinimumCharacters: Int) {
        self.animatedTailLimit = animatedTailLimit
        self.firstPreviewMinimumCharacters = firstPreviewMinimumCharacters
    }

    var isEmpty: Bool {
        displayedDraft.isEmpty
    }

    /// 快照纪律入口：稳定区只追加（左侧允许窗口裁剪），可变尾部允许原位替换。
    ///
    /// 与 `setTarget` 的字符串猜测式 diff 不同，这里依赖 `PreviewDisplaySnapshot` 的契约：
    /// `stableCharacterCount` 单调递增，稳定窗口内容不改写。displayedDraft 恒为 targetDraft 的前缀，
    /// 打字机只负责推进显示长度；尾部内容变化通过前缀关系自然原位生效。
    func setSnapshot(
        stableCharacterCount newStableCount: Int,
        stableWindowText: String,
        volatileTailText: String
    ) -> CapsuleTextBufferUpdate {
        let composed = stableWindowText + volatileTailText
        guard !composed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reset()
            return .reset
        }

        realtimeRevisionCount += 1
        if displayedDraft.isEmpty {
            if realtimeRevisionCount == 1, composed.count < firstPreviewMinimumCharacters {
                stableAnchorCount = newStableCount
                return .ignored
            }
            let initialCount = composed.count > animatedTailLimit
                ? composed.count - animatedTailLimit
                : min(2, composed.count)
            displayedDraft = prefix(of: composed, count: initialCount)
            targetDraft = composed
            stableTargetLength = stableWindowText.count
            stableAnchorCount = newStableCount
            return .updated(
                fadeStartIndex: 0,
                needsDraftTimer: displayedDraft != targetDraft,
                shouldStopDraftTimer: false
            )
        }

        // 稳定区增量与窗口左裁剪：旧稳定窗口 + 新增稳定字符 − 新稳定窗口 = 从左侧滚出的字符数。
        let appended = max(0, newStableCount - stableAnchorCount)
        let leftTrim = max(0, min(displayedDraft.count, stableTargetLength + appended - stableWindowText.count))
        var displayedCount = min(displayedDraft.count - leftTrim, composed.count)
        // 动画欠账上限：大批新文本立即追到只剩 animatedTailLimit（Build 648 规则）。
        displayedCount = max(displayedCount, composed.count - animatedTailLimit)
        displayedCount = max(0, min(displayedCount, composed.count))

        targetDraft = composed
        displayedDraft = prefix(of: composed, count: displayedCount)
        stableTargetLength = stableWindowText.count
        stableAnchorCount = max(stableAnchorCount, newStableCount)

        guard displayedDraft != targetDraft else {
            return .updated(fadeStartIndex: nil, needsDraftTimer: false, shouldStopDraftTimer: true)
        }
        return .updated(
            fadeStartIndex: displayedDraft.count,
            needsDraftTimer: true,
            shouldStopDraftTimer: false
        )
    }

    func setTarget(_ draft: String) -> CapsuleTextBufferUpdate {
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            reset()
            return .reset
        }

        realtimeRevisionCount += 1
        if displayedDraft.isEmpty,
           realtimeRevisionCount == 1,
           normalized.count < firstPreviewMinimumCharacters {
            return .ignored
        }

        if displayedDraft.isEmpty {
            let initialCount = normalized.count > animatedTailLimit
                ? normalized.count - animatedTailLimit
                : min(2, normalized.count)
            displayedDraft = prefix(of: normalized, count: initialCount)
            targetDraft = normalized
            stableTargetLength = targetDraft.count
            return .updated(
                fadeStartIndex: 0,
                needsDraftTimer: displayedDraft != targetDraft,
                shouldStopDraftTimer: false
            )
        }

        let refreshed = refreshedDisplayPreservingLength(with: normalized)
        if refreshed != displayedDraft {
            displayedDraft = refreshed
        }

        if normalized.count > displayedDraft.count {
            let catchUpCount = max(displayedDraft.count, normalized.count - animatedTailLimit)
            if catchUpCount > displayedDraft.count {
                displayedDraft = prefix(of: normalized, count: catchUpCount)
            }
            targetDraft = normalized
            stableTargetLength = targetDraft.count
            return .updated(
                fadeStartIndex: displayedDraft.count,
                needsDraftTimer: displayedDraft != targetDraft,
                shouldStopDraftTimer: false
            )
        }

        targetDraft = displayedDraft
        stableTargetLength = targetDraft.count
        return .updated(
            fadeStartIndex: nil,
            needsDraftTimer: false,
            shouldStopDraftTimer: true
        )
    }

    func advance() -> CapsuleTextBufferAdvance {
        guard displayedDraft != targetDraft else {
            return .finished
        }

        if !targetDraft.hasPrefix(displayedDraft) {
            displayedDraft = refreshedDisplayPreservingLength(with: targetDraft)
            if targetDraft.count <= displayedDraft.count {
                return .refreshedAndFinished
            }
        }

        let previousCount = displayedDraft.count
        displayedDraft = String(targetDraft.prefix(min(targetDraft.count, displayedDraft.count + 1)))
        if displayedDraft.count > previousCount {
            return .advanced(fadeStartIndex: previousCount)
        }
        return .advanced(fadeStartIndex: nil)
    }

    private func reset() {
        targetDraft = ""
        displayedDraft = ""
        realtimeRevisionCount = 0
        stableTargetLength = 0
        stableAnchorCount = 0
    }

    private func refreshedDisplayPreservingLength(with normalized: String) -> String {
        let current = Array(displayedDraft)
        let latest = Array(normalized)
        guard !current.isEmpty else { return "" }
        var refreshed: [Character] = []
        refreshed.reserveCapacity(current.count)
        for index in current.indices {
            if index < latest.count {
                refreshed.append(latest[index])
            } else {
                refreshed.append(current[index])
            }
        }
        return String(refreshed)
    }

    private func prefix(of text: String, count: Int) -> String {
        String(text.prefix(max(0, min(count, text.count))))
    }
}
