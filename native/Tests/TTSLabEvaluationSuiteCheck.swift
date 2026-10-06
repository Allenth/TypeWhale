import Foundation

@main
struct TTSLabEvaluationSuiteCheck {
    static func main() throws {
        precondition(
            TTSLabEvaluationSuite.samples.map(\.id)
                == ["zh-short-v1", "en-short-v1", "mixed-v1", "zh-long-v1"]
        )
        precondition(Set(TTSLabEvaluationSuite.samples.map(\.id)).count == 4)

        var generator = SeededGenerator(seed: 42)
        let candidates = TTSLabEvaluationSuite.blindCandidates(
            modelIDs: ["kokoro", "qwen", "voxcpm"],
            random: &generator
        )
        precondition(Set(candidates.map(\.label)) == Set(["A", "B", "C"]))
        precondition(Set(candidates.map(\.modelID)) == Set(["kokoro", "qwen", "voxcpm"]))
        for candidate in candidates {
            let filename = candidate.outputURL(
                root: URL(fileURLWithPath: "/tmp/blind"),
                sampleID: "zh-short-v1"
            ).lastPathComponent
            precondition(!filename.contains(candidate.modelID))
            precondition(filename.hasSuffix("-zh-short-v1.wav"))
        }
        print("TTSLabEvaluationSuiteCheck passed")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
