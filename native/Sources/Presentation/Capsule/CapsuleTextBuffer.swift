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

    init(animatedTailLimit: Int, firstPreviewMinimumCharacters: Int) {
        self.animatedTailLimit = animatedTailLimit
        self.firstPreviewMinimumCharacters = firstPreviewMinimumCharacters
    }

    var isEmpty: Bool {
        displayedDraft.isEmpty
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
            targetDraft = normalized
            return .updated(
                fadeStartIndex: displayedDraft.count,
                needsDraftTimer: displayedDraft != targetDraft,
                shouldStopDraftTimer: false
            )
        }

        targetDraft = displayedDraft
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
