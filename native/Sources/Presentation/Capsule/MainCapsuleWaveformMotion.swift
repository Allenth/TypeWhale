import Foundation

struct MainCapsuleWaveformMotion: Equatable {
    private static let defaultBandCount = 7
    private static let defaultBaseline: Float = 0.08
    private static let defaultAttack: Float = 0.52
    private static let defaultRelease: Float = 0.16

    private(set) var bands: [Float]
    private let baseline: Float
    private let attack: Float
    private let release: Float

    init(
        count: Int = Self.defaultBandCount,
        baseline: Float = Self.defaultBaseline,
        attack: Float = Self.defaultAttack,
        release: Float = Self.defaultRelease
    ) {
        let safeCount = max(0, count)
        self.bands = Array(repeating: baseline, count: safeCount)
        self.baseline = baseline
        self.attack = attack
        self.release = release
    }

    mutating func apply(_ rawBands: [Float]) {
        for index in bands.indices {
            let target = index < rawBands.count ? rawBands[index] : baseline
            let smoothing = target > bands[index] ? attack : release
            bands[index] += (target - bands[index]) * smoothing
        }
    }

    mutating func reset() {
        for index in bands.indices {
            bands[index] = baseline
        }
    }
}
