import Foundation

/// Stateful IMA/DVI ADPCM decoder used by the public Google TV Remote ATVV wire format.
/// ATVV transmits the high nibble before the low nibble.
struct RemoteADPCMDecoder {
    private static let indexTable = [-1, -1, -1, -1, 2, 4, 6, 8]
    private static let stepTable = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
        19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1_060, 1_166, 1_282, 1_411, 1_552, 1_707, 1_878, 2_066,
        2_272, 2_494, 2_740, 3_008, 3_307, 3_638, 4_002, 4_402, 4_842, 5_327,
        5_860, 6_446, 7_091, 7_800, 8_580, 9_438, 10_382, 11_420, 12_562, 13_818,
        15_200, 16_720, 18_392, 20_231, 22_254, 24_479, 26_927, 29_620, 32_767,
    ]

    private var predictor = 0
    private var stepIndex = 0

    mutating func reset(predictor: Int16, stepIndex: UInt8) {
        self.predictor = Int(predictor)
        self.stepIndex = min(Self.stepTable.count - 1, Int(stepIndex))
    }

    mutating func decode<S: Sequence>(_ bytes: S) -> [Int16] where S.Element == UInt8 {
        var samples: [Int16] = []
        samples.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            samples.append(decode(nibble: Int(byte >> 4)))
            samples.append(decode(nibble: Int(byte & 0x0F)))
        }
        return samples
    }

    private mutating func decode(nibble: Int) -> Int16 {
        let step = Self.stepTable[stepIndex]
        var delta = step >> 3
        if nibble & 0x04 != 0 { delta += step }
        if nibble & 0x02 != 0 { delta += step >> 1 }
        if nibble & 0x01 != 0 { delta += step >> 2 }

        predictor += nibble & 0x08 == 0 ? delta : -delta
        predictor = min(Int(Int16.max), max(Int(Int16.min), predictor))

        stepIndex += Self.indexTable[nibble & 0x07]
        stepIndex = min(Self.stepTable.count - 1, max(0, stepIndex))
        return Int16(predictor)
    }
}
