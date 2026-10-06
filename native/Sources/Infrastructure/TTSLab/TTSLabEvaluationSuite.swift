import Foundation

struct TTSLabEvaluationSample: Equatable, Identifiable {
    let id: String
    let text: String
}

struct TTSLabBlindCandidate: Equatable {
    let label: String
    let modelID: String

    func outputURL(root: URL, sampleID: String) -> URL {
        root.appendingPathComponent("\(label)-\(sampleID).wav")
    }
}

enum TTSLabEvaluationSuite {
    static let samples = [
        TTSLabEvaluationSample(
            id: "zh-short-v1",
            text: "你好，欢迎使用 TypeWhale 本地朗读测试。"
        ),
        TTSLabEvaluationSample(
            id: "en-short-v1",
            text: "The quick brown fox jumps over the lazy dog."
        ),
        TTSLabEvaluationSample(
            id: "mixed-v1",
            text: "TypeWhale 使用 Core ML、GitHub 和 ChatGPT 完成本地测试。"
        ),
        TTSLabEvaluationSample(
            id: "zh-long-v1",
            text: "2026年7月28日上午9点30分，TypeWhale 将读取一段包含数字、日期、英文缩写和标点的长文本。我们先比较启动速度、首段声音出现的时间与自然度，再观察连续朗读时是否稳定，最后记录内存占用，在体验与资源之间找到平衡。"
        ),
    ]

    static func blindCandidates(
        modelIDs: [String],
        random: inout some RandomNumberGenerator
    ) -> [TTSLabBlindCandidate] {
        modelIDs.shuffled(using: &random).enumerated().map { index, modelID in
            TTSLabBlindCandidate(
                label: blindLabel(index),
                modelID: modelID
            )
        }
    }

    private static func blindLabel(_ index: Int) -> String {
        var value = index
        var label = ""
        repeat {
            label.insert(
                Character(UnicodeScalar(65 + value % 26)!),
                at: label.startIndex
            )
            value = value / 26 - 1
        } while value >= 0
        return label
    }
}
