import Foundation

struct PreviewTranscriptReducer: Sendable {
    private let sessionID: UUID
    private let epoch: Int
    private let visibleCharacterLimit: Int
    private var pendingCorrection: PreviewRecognitionResult?
    private var confirmedTokens: [String] = []
    private var confirmedThroughTime: TimeInterval = -.greatestFiniteMagnitude
    private var provisionalFastResultByChunk: [Int: PreviewRecognitionResult] = [:]
    private var confirmedFastThroughChunkID = -1
    private(set) var state: PreviewTranscriptState
    private(set) var lastOwnershipTransition: PreviewOwnershipTransition?

    init(sessionID: UUID, epoch: Int, visibleCharacterLimit: Int = 160) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.visibleCharacterLimit = max(1, visibleCharacterLimit)
        self.state = PreviewTranscriptState(
            confirmedSegments: [],
            mutableTailText: "",
            displayText: "",
            displayRevision: 0,
            recoveryRequested: false,
            confirmedCharacterCount: 0
        )
    }

    mutating func apply(_ event: PreviewTranscriptEvent) -> PreviewTranscriptState? {
        lastOwnershipTransition = nil
        switch event {
        case .fast(let result):
            guard accepts(result) else {
                recordTransition(.rejectedIdentity)
                return nil
            }
            state.recoveryRequested = false
            guard result.chunkID > confirmedFastThroughChunkID else {
                recordTransition(.ignoredStaleFast)
                return nil
            }
            provisionalFastResultByChunk[result.chunkID] = result
            state.mutableTailText = provisionalFastProjection()
            recordTransition(.fastStored)
            return publishIfChanged()

        case .correction(let result):
            guard accepts(result) else {
                recordTransition(.rejectedIdentity)
                return nil
            }
            guard let previous = pendingCorrection else {
                pendingCorrection = result
                state.mutableTailText = preferredTail(for: result, correctionText: result.text)
                recordTransition(.correctionPrimed, replacementRange: result.audioRange)
                return publishIfChanged()
            }

            if let alignment = timestampAlignment(previous: previous, current: result) {
                let confirmationTime = min(alignment.seamTime, previous.boundary?.time ?? alignment.seamTime)
                guard confirmationTime + 0.75 >= confirmedThroughTime else {
                    pendingCorrection = result
                    state.recoveryRequested = true
                    state.mutableTailText = preferredTail(for: result, correctionText: result.text)
                    recordTransition(
                        .correctionRecovery,
                        replacementRange: result.audioRange,
                        confirmedThroughTime: confirmedThroughTime
                    )
                    return publishIfChanged(force: true)
                }
                let previousTimestamps = previous.validatedTokenTimestamps ?? []
                let newConfirmed = previous.tokens.enumerated().compactMap { index, token -> String? in
                    let absoluteTime = previous.audioRange.start + TimeInterval(previousTimestamps[index])
                    return absoluteTime > confirmedThroughTime && absoluteTime <= confirmationTime + 0.001
                        ? token
                        : nil
                }
                let promotedFast = promoteFastUnits(
                    before: previous.audioRange.start,
                    through: previous.chunkID
                )
                var confirmedRange: PreviewAudioRange?
                if !newConfirmed.isEmpty {
                    let range = PreviewAudioRange(
                        start: max(previous.audioRange.start, confirmedThroughTime.isFinite ? confirmedThroughTime : previous.audioRange.start),
                        end: confirmationTime
                    )
                    state.confirmedSegments.append(PreviewTranscriptSegment(
                        id: UUID(),
                        text: newConfirmed.joined(),
                        audioRange: range
                    ))
                    confirmedRange = range
                    confirmedTokens.append(contentsOf: newConfirmed)
                    state.confirmedCharacterCount += newConfirmed.joined().count
                }
                confirmedThroughTime = max(confirmedThroughTime, confirmationTime)
                let currentTimestamps = result.validatedTokenTimestamps ?? []
                let tailUnits = result.tokens.enumerated().compactMap { index, token -> String? in
                    let absoluteTime = result.audioRange.start + TimeInterval(currentTimestamps[index])
                    return absoluteTime > confirmationTime + 0.001 ? token : nil
                }
                let removedFastChunkIDs = confirmFastChunks(
                    through: previous.chunkID,
                    correctionCoverage: result.audioRange
                )
                state.mutableTailText = preferredTail(for: result, correctionText: tailUnits.joined())
                state.recoveryRequested = promotedFast.usedEstimatedTimes
                pendingCorrection = result
                recordTransition(
                    .correctionMerged,
                    replacementRange: result.audioRange,
                    confirmedRange: confirmedRange,
                    confirmedThroughTime: confirmedThroughTime,
                    promotedFastCharacterCount: promotedFast.characterCount,
                    promotedFastRange: promotedFast.audioRange,
                    promotedFastText: promotedFast.text,
                    removedFastChunkIDs: removedFastChunkIDs
                )
                return publishIfChanged()
            }

            let previousUnits = comparisonUnits(for: previous)
            let currentUnits = comparisonUnits(for: result)
            let overlapCount = longestSuffixPrefixOverlap(previousUnits, currentUnits)
            guard overlapCount >= 2 else {
                pendingCorrection = result
                state.recoveryRequested = true
                state.mutableTailText = preferredTail(for: result, correctionText: result.text)
                recordTransition(
                    .correctionRecovery,
                    replacementRange: result.audioRange,
                    confirmedThroughTime: confirmedThroughTime.isFinite ? confirmedThroughTime : nil
                )
                return publishIfChanged(force: true)
            }
            let alreadyConfirmedOverlap = longestSuffixPrefixOverlap(confirmedTokens, previousUnits)
            let newConfirmedUnits = Array(previousUnits.dropFirst(alreadyConfirmedOverlap))
            let promotedFast = promoteFastUnits(
                before: previous.audioRange.start,
                through: previous.chunkID
            )
            var confirmedRange: PreviewAudioRange?
            if !newConfirmedUnits.isEmpty {
                state.confirmedSegments.append(PreviewTranscriptSegment(
                    id: UUID(),
                    text: newConfirmedUnits.joined(),
                    audioRange: previous.audioRange
                ))
                confirmedRange = previous.audioRange
                confirmedTokens.append(contentsOf: newConfirmedUnits)
                state.confirmedCharacterCount += newConfirmedUnits.joined().count
            }
            let tailUnits = Array(currentUnits.dropFirst(overlapCount))
            let removedFastChunkIDs = confirmFastChunks(
                through: previous.chunkID,
                correctionCoverage: result.audioRange
            )
            state.mutableTailText = preferredTail(for: result, correctionText: tailUnits.joined())
            state.recoveryRequested = promotedFast.usedEstimatedTimes
            pendingCorrection = result
            recordTransition(
                .correctionMerged,
                replacementRange: result.audioRange,
                confirmedRange: confirmedRange,
                confirmedThroughTime: confirmedThroughTime.isFinite ? confirmedThroughTime : nil,
                promotedFastCharacterCount: promotedFast.characterCount,
                promotedFastRange: promotedFast.audioRange,
                promotedFastText: promotedFast.text,
                removedFastChunkIDs: removedFastChunkIDs
            )
            return publishIfChanged()
        }
    }

    private mutating func recordTransition(
        _ decision: PreviewOwnershipDecision,
        replacementRange: PreviewAudioRange? = nil,
        confirmedRange: PreviewAudioRange? = nil,
        confirmedThroughTime: TimeInterval? = nil,
        promotedFastCharacterCount: Int = 0,
        promotedFastRange: PreviewAudioRange? = nil,
        promotedFastText: String? = nil,
        removedFastChunkIDs: [Int] = []
    ) {
        lastOwnershipTransition = PreviewOwnershipTransition(
            decision: decision,
            replacementRange: replacementRange,
            confirmedRange: confirmedRange,
            confirmedThroughTime: confirmedThroughTime,
            promotedFastCharacterCount: promotedFastCharacterCount,
            promotedFastRange: promotedFastRange,
            promotedFastText: promotedFastText,
            removedFastChunkIDs: removedFastChunkIDs
        )
    }

    private func accepts(_ result: PreviewRecognitionResult) -> Bool {
        result.sessionID == sessionID && result.epoch == epoch
    }

    private func comparisonUnits(for result: PreviewRecognitionResult) -> [String] {
        if result.validatedTokenTimestamps != nil, !result.tokens.isEmpty {
            return result.tokens
        }
        if !result.tokens.isEmpty {
            return result.tokens
        }
        return result.text.map(String.init)
    }

    private func longestSuffixPrefixOverlap(_ lhs: [String], _ rhs: [String]) -> Int {
        let maximum = min(lhs.count, rhs.count)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1) {
            if Array(lhs.suffix(length)) == Array(rhs.prefix(length)) {
                return length
            }
        }
        return 0
    }

    private func provisionalFastProjection() -> String {
        provisionalFastResultByChunk.keys.sorted().compactMap { provisionalFastResultByChunk[$0]?.text }.joined()
    }

    private mutating func confirmFastChunks(
        through chunkID: Int,
        correctionCoverage: PreviewAudioRange
    ) -> [Int] {
        guard chunkID != .max else { return [] }
        let removable = provisionalFastResultByChunk.compactMap { key, result -> Int? in
            guard key <= chunkID else { return nil }
            let coveredByConfirmation = result.audioRange.end <= confirmedThroughTime + 0.001
            let coveredByCurrentCorrection = result.audioRange.start >= correctionCoverage.start - 0.001
                && result.audioRange.end <= correctionCoverage.end + 0.001
            guard coveredByConfirmation || coveredByCurrentCorrection else { return nil }
            return key
        }
        for key in removable {
            provisionalFastResultByChunk.removeValue(forKey: key)
        }
        if let lastRemoved = removable.max() {
            confirmedFastThroughChunkID = max(confirmedFastThroughChunkID, lastRemoved)
        }
        return removable.sorted()
    }

    /// correction 的窗口可能从一块中间开始。先把窗口开始前仍由 fast 独占的文字转为稳定内容，
    /// 再允许 correction 接管它真正覆盖的时间范围，避免“部分确认、整块删除”。
    private mutating func promoteFastUnits(
        before cutoff: TimeInterval,
        through chunkID: Int
    ) -> (usedEstimatedTimes: Bool, characterCount: Int, audioRange: PreviewAudioRange?, text: String?) {
        guard cutoff.isFinite else { return (false, 0, nil, nil) }
        let candidates = provisionalFastResultByChunk
            .filter { $0.key <= chunkID }
            .sorted { lhs, rhs in
                if lhs.value.audioRange.start == rhs.value.audioRange.start {
                    return lhs.key < rhs.key
                }
                return lhs.value.audioRange.start < rhs.value.audioRange.start
            }

        var promoted: [String] = []
        var promotedStart: TimeInterval?
        var promotedEnd: TimeInterval?
        var usedEstimatedTimes = false
        for (_, fast) in candidates {
            let timed = timedUnits(for: fast)
            let selected = timed.units.filter { unit in
                unit.time > confirmedThroughTime + 0.001
                    && unit.time < cutoff - 0.001
            }
            guard !selected.isEmpty else { continue }
            promoted.append(contentsOf: selected.map(\.text))
            promotedStart = min(promotedStart ?? selected[0].time, selected[0].time)
            promotedEnd = max(promotedEnd ?? selected[selected.count - 1].time, selected[selected.count - 1].time)
            if timed.usedEstimatedTimes {
                usedEstimatedTimes = true
            }
        }
        guard !promoted.isEmpty else { return (false, 0, nil, nil) }
        let text = promoted.joined()
        let range = PreviewAudioRange(
            start: promotedStart ?? max(0, confirmedThroughTime),
            end: promotedEnd ?? cutoff
        )
        state.confirmedSegments.append(PreviewTranscriptSegment(
            id: UUID(),
            text: text,
            audioRange: range
        ))
        confirmedTokens.append(contentsOf: promoted)
        state.confirmedCharacterCount += text.count
        return (usedEstimatedTimes, text.count, range, text)
    }

    private func timedUnits(
        for result: PreviewRecognitionResult
    ) -> (units: [(text: String, time: TimeInterval)], usedEstimatedTimes: Bool) {
        let units = comparisonUnits(for: result)
        guard !units.isEmpty else { return ([], false) }
        if let timestamps = result.validatedTokenTimestamps,
           timestamps.count == units.count {
            return (units.enumerated().map { index, unit in
                (unit, result.audioRange.start + TimeInterval(timestamps[index]))
            }, false)
        }
        let duration = result.audioRange.duration
        return (units.enumerated().map { index, unit in
            let fraction = (Double(index) + 0.5) / Double(units.count)
            return (unit, result.audioRange.start + duration * fraction)
        }, true)
    }

    private func preferredTail(for result: PreviewRecognitionResult, correctionText: String) -> String {
        if result.sourceLane == .stopTail { return correctionText }
        let fastProjection = provisionalFastProjection()
        return fastProjection.isEmpty ? correctionText : fastProjection
    }

    private func timestampAlignment(
        previous: PreviewRecognitionResult,
        current: PreviewRecognitionResult
    ) -> (currentEndIndex: Int, seamTime: TimeInterval)? {
        guard let previousTimestamps = previous.validatedTokenTimestamps,
              let currentTimestamps = current.validatedTokenTimestamps,
              !previous.tokens.isEmpty,
              !current.tokens.isEmpty else { return nil }

        var bestLength = 0
        var bestCurrentEnd = -1
        var bestSeam = 0.0
        for previousStart in previous.tokens.indices {
            for currentStart in current.tokens.indices {
                var length = 0
                while previousStart + length < previous.tokens.count,
                      currentStart + length < current.tokens.count {
                    let previousIndex = previousStart + length
                    let currentIndex = currentStart + length
                    guard previous.tokens[previousIndex] == current.tokens[currentIndex] else { break }
                    let previousAbsolute = previous.audioRange.start + TimeInterval(previousTimestamps[previousIndex])
                    let currentAbsolute = current.audioRange.start + TimeInterval(currentTimestamps[currentIndex])
                    guard abs(previousAbsolute - currentAbsolute) <= 0.75 else { break }
                    length += 1
                    if length > bestLength {
                        bestLength = length
                        bestCurrentEnd = currentIndex
                        bestSeam = min(previousAbsolute, currentAbsolute)
                    }
                }
            }
        }
        guard bestLength >= 2, bestCurrentEnd >= 0 else { return nil }
        return (bestCurrentEnd, bestSeam)
    }

    private mutating func publishIfChanged(force: Bool = false) -> PreviewTranscriptState? {
        // 尾部优先占用可见窗口；剩余额度从最近的确认片段向前回填稳定窗口。
        let volatileVisible = String(state.mutableTailText.suffix(visibleCharacterLimit))
        var remaining = visibleCharacterLimit - volatileVisible.count
        var recentConfirmed = ""
        for segment in state.confirmedSegments.reversed() where remaining > 0 {
            let suffix = String(segment.text.suffix(remaining))
            recentConfirmed = suffix + recentConfirmed
            remaining -= suffix.count
        }
        let bounded = recentConfirmed + volatileVisible
        // 内容相同但确认边界前移时也要发布：显示层需要更新稳定/可变分界。
        let stableBoundaryAdvanced = state.confirmedCharacterCount != (state.displaySnapshot?.stableCharacterCount ?? 0)
        guard force || bounded != state.displayText || stableBoundaryAdvanced else { return nil }
        state.displayText = bounded
        state.displayRevision += 1
        state.displaySnapshot = PreviewDisplaySnapshot(
            revision: state.displayRevision,
            stableCharacterCount: state.confirmedCharacterCount,
            stableWindowText: recentConfirmed,
            volatileTailText: volatileVisible
        )
        return state
    }

    mutating func markRecoveryRequested() -> PreviewTranscriptState {
        state.recoveryRequested = true
        return state
    }
}
