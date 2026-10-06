import Foundation

struct SenseVoiceSnapshotRecognition: Equatable, Sendable {
    let text: String
    let tokens: [String]
    let tokenTimestamps: [Float]?
    let audioRange: TranscriptionAudioRange

    var validatedTokenTimestamps: [Float]? {
        guard let tokenTimestamps,
              tokenTimestamps.count == tokens.count,
              tokenTimestamps.allSatisfy({
                  $0.isFinite && $0 >= 0 && TimeInterval($0) <= audioRange.duration + 0.25
              }) else { return nil }
        for index in tokenTimestamps.indices.dropFirst()
        where tokenTimestamps[index] < tokenTimestamps[index - 1] {
            return nil
        }
        return tokenTimestamps
    }
}

struct SenseVoiceBoundaryReconciliation: Equatable, Sendable {
    let confirmedText: String
    let newlyConfirmedText: String
    let volatileTailText: String
    let confirmedThroughTime: TimeInterval?
    let recoveryRequired: Bool
    let seamConfidence: SeamConfidence
}

enum SeamConfidence: Equatable, Sendable {
    case tokenVerified
    case boundaryCorrected
    case timeOverlapOnly
    case noOverlapRecoveryTriggered
}

enum SenseVoiceBoundaryReconciliationStrategy: Equatable, Sendable {
    case audioTime
    case lexicalOverlap
}

/// 将相邻 SenseVoice 快照按音频时间组装；词面改写不影响稳定边界向前推进。
struct SenseVoiceBoundaryReconciler: Sendable {
    private let strategy: SenseVoiceBoundaryReconciliationStrategy
    private var previous: SenseVoiceSnapshotRecognition?
    private var confirmedTokens: [String] = []
    private var confirmedThroughTime: TimeInterval?
    private var volatileTailText = ""

    var currentConfirmedText: String { confirmedTokens.joined() }
    var currentVolatileTailText: String { volatileTailText }
    var currentDisplayText: String { currentConfirmedText + currentVolatileTailText }

    init(strategy: SenseVoiceBoundaryReconciliationStrategy = .lexicalOverlap) {
        self.strategy = strategy
    }

    mutating func consume(
        _ current: SenseVoiceSnapshotRecognition
    ) -> SenseVoiceBoundaryReconciliation {
        guard let previous else {
            self.previous = current
            volatileTailText = current.text
            return result(volatileTail: current.text)
        }
        if strategy == .lexicalOverlap {
            return consumeLexical(current, previous: previous)
        }

        let epsilon = 0.001
        if current.audioRange.end < previous.audioRange.end - epsilon
            || (abs(current.audioRange.end - previous.audioRange.end) <= epsilon
                && current.audioRange.start >= previous.audioRange.start) {
            return result(volatileTail: volatileTailText)
        }

        let overlapStart = max(previous.audioRange.start, current.audioRange.start)
        let overlapEnd = min(previous.audioRange.end, current.audioRange.end)
        let lowerBound = confirmedThroughTime ?? -.greatestFiniteMagnitude

        guard overlapEnd > overlapStart + epsilon else {
            let newlyConfirmed = timedUnits(for: previous).compactMap { unit in
                unit.time > lowerBound + epsilon ? unit.text : nil
            }
            confirmedTokens.append(contentsOf: newlyConfirmed)
            confirmedThroughTime = max(confirmedThroughTime ?? previous.audioRange.end, previous.audioRange.end)
            self.previous = current
            volatileTailText = current.text
            return result(
                newlyConfirmed: newlyConfirmed.joined(),
                volatileTail: current.text,
                recoveryRequired: true,
                seamConfidence: .noOverlapRecoveryTriggered
            )
        }

        let seamTime = (overlapStart + overlapEnd) / 2
        let confirmationSource = current.audioRange.start < previous.audioRange.start
            ? current
            : previous
        let newlyConfirmed = timedUnits(for: confirmationSource).compactMap { unit in
            unit.time > lowerBound + epsilon && unit.time <= seamTime + epsilon
                ? unit.text
                : nil
        }
        confirmedTokens.append(contentsOf: newlyConfirmed)
        confirmedThroughTime = max(confirmedThroughTime ?? seamTime, seamTime)
        let tail = timedUnits(for: current).compactMap { unit in
            unit.time > seamTime + epsilon ? unit.text : nil
        }
        self.previous = current
        volatileTailText = tail.joined()
        return result(
            newlyConfirmed: newlyConfirmed.joined(),
            volatileTail: volatileTailText
        )
    }

    mutating func consumeBoundaryCorrection(
        _ current: SenseVoiceSnapshotRecognition
    ) -> SenseVoiceBoundaryReconciliation {
        previous = current
        volatileTailText = current.text
        return result(
            volatileTail: current.text,
            seamConfidence: .boundaryCorrected
        )
    }

    private func result(
        newlyConfirmed: String = "",
        volatileTail: String,
        recoveryRequired: Bool = false,
        seamConfidence: SeamConfidence = .timeOverlapOnly
    ) -> SenseVoiceBoundaryReconciliation {
        SenseVoiceBoundaryReconciliation(
            confirmedText: confirmedTokens.joined(),
            newlyConfirmedText: newlyConfirmed,
            volatileTailText: volatileTail,
            confirmedThroughTime: confirmedThroughTime,
            recoveryRequired: recoveryRequired,
            seamConfidence: seamConfidence
        )
    }

    private func timedUnits(
        for recognition: SenseVoiceSnapshotRecognition
    ) -> [(text: String, time: TimeInterval)] {
        let units = recognition.tokens.isEmpty
            ? recognition.text.map(String.init)
            : recognition.tokens
        guard !units.isEmpty else { return [] }
        if let timestamps = recognition.validatedTokenTimestamps {
            return zip(units, timestamps).map { unit, timestamp in
                (unit, recognition.audioRange.start + TimeInterval(timestamp))
            }
        }
        let duration = recognition.audioRange.duration
        return units.enumerated().map { index, unit in
            let fraction = Double(index + 1) / Double(units.count)
            return (unit, recognition.audioRange.start + duration * fraction)
        }
    }

    private mutating func consumeLexical(
        _ current: SenseVoiceSnapshotRecognition,
        previous: SenseVoiceSnapshotRecognition
    ) -> SenseVoiceBoundaryReconciliation {
        if let alignment = timestampAlignment(previous: previous, current: current) {
            let priorTimes = previous.validatedTokenTimestamps ?? []
            let lowerBound = confirmedThroughTime ?? -.greatestFiniteMagnitude
            let newlyConfirmed = previous.tokens.enumerated().compactMap { index, token in
                let absolute = previous.audioRange.start + TimeInterval(priorTimes[index])
                return absolute > lowerBound && absolute <= alignment.seamTime + 0.001
                    ? token
                    : nil
            }
            confirmedTokens.append(contentsOf: newlyConfirmed)
            confirmedThroughTime = max(confirmedThroughTime ?? alignment.seamTime, alignment.seamTime)
            let currentTimes = current.validatedTokenTimestamps ?? []
            let tail = current.tokens.enumerated().compactMap { index, token in
                let absolute = current.audioRange.start + TimeInterval(currentTimes[index])
                return absolute > alignment.seamTime + 0.001 ? token : nil
            }
            self.previous = current
            volatileTailText = tail.joined()
            return result(
                newlyConfirmed: newlyConfirmed.joined(),
                volatileTail: volatileTailText,
                seamConfidence: .tokenVerified
            )
        }

        let previousUnits = lexicalUnits(for: previous)
        let currentUnits = lexicalUnits(for: current)
        let overlap = longestSuffixPrefixOverlap(previousUnits, currentUnits)
        guard overlap >= 2 else {
            self.previous = current
            volatileTailText = current.text
            return result(
                volatileTail: current.text,
                recoveryRequired: true,
                seamConfidence: .noOverlapRecoveryTriggered
            )
        }

        let alreadyConfirmed = longestSuffixPrefixOverlap(confirmedTokens, previousUnits)
        let newlyConfirmed = Array(previousUnits.dropFirst(alreadyConfirmed))
        confirmedTokens.append(contentsOf: newlyConfirmed)
        let tail = Array(currentUnits.dropFirst(overlap))
        self.previous = current
        volatileTailText = tail.joined()
        return result(
            newlyConfirmed: newlyConfirmed.joined(),
            volatileTail: volatileTailText,
            seamConfidence: .tokenVerified
        )
    }

    private func lexicalUnits(for recognition: SenseVoiceSnapshotRecognition) -> [String] {
        recognition.tokens.isEmpty ? recognition.text.map(String.init) : recognition.tokens
    }

    private func longestSuffixPrefixOverlap(_ lhs: [String], _ rhs: [String]) -> Int {
        let maximum = min(lhs.count, rhs.count)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1) {
            if Array(lhs.suffix(length)) == Array(rhs.prefix(length)) { return length }
        }
        return 0
    }

    private func timestampAlignment(
        previous: SenseVoiceSnapshotRecognition,
        current: SenseVoiceSnapshotRecognition
    ) -> (seamTime: TimeInterval, length: Int)? {
        guard let previousTimes = previous.validatedTokenTimestamps,
              let currentTimes = current.validatedTokenTimestamps,
              !previous.tokens.isEmpty,
              !current.tokens.isEmpty else { return nil }

        var bestLength = 0
        var bestSeam = 0.0
        for previousStart in previous.tokens.indices {
            for currentStart in current.tokens.indices {
                var length = 0
                while previousStart + length < previous.tokens.count,
                      currentStart + length < current.tokens.count {
                    let previousIndex = previousStart + length
                    let currentIndex = currentStart + length
                    guard previous.tokens[previousIndex] == current.tokens[currentIndex] else { break }
                    let previousAbsolute = previous.audioRange.start + TimeInterval(previousTimes[previousIndex])
                    let currentAbsolute = current.audioRange.start + TimeInterval(currentTimes[currentIndex])
                    guard abs(previousAbsolute - currentAbsolute) <= 0.75 else { break }
                    length += 1
                    if length > bestLength {
                        bestLength = length
                        bestSeam = min(previousAbsolute, currentAbsolute)
                    }
                }
            }
        }
        return bestLength >= 2 ? (bestSeam, bestLength) : nil
    }
}
