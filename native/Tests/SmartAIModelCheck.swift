import Foundation

@main
struct SmartAIModelCheck {
    static func main() {
        precondition(SmartAIModel.defaultModel == .ollamaQwen35B)
        precondition(SmartAIModel.allCases.map(\.rawValue) == [
            "ollama-qwen3.6-35b-mlx",
            "deepseek-v4-flash",
        ])
        precondition(SmartAIModel.ollamaQwen35B.provider == .ollama)
        precondition(SmartAIModel.ollamaQwen35B.engineModelName == "qwen3.6:35b-mlx")
        precondition(SmartAIModel.deepSeekV4Flash.provider == .deepSeek)
        precondition(!SmartAIModel.ollamaQwen35B.supportsUsageSummary)
        precondition(SmartAIModel.deepSeekV4Flash.supportsUsageSummary)
        precondition(SmartAIModel.fromStoredRawValue("MiniMax-M2") == .deepSeekV4Flash)
        precondition(SmartAIModel.fromStoredRawValue("MiniMax-M2.5-highspeed") == .deepSeekV4Flash)
        precondition(SmartAIModel.fromStoredRawValue("qwen3.6:35b-mlx") == .ollamaQwen35B)
        precondition(SmartAIModel.fromStoredRawValue("Qwen3.6-35B-A3B-MLX-8bit") == .ollamaQwen35B)
        precondition(SmartAIModel.fromStoredRawValue("qwen3:8b") == .ollamaQwen35B)
        precondition(SmartAIModel.fromStoredRawValue("ollama-qwen3-8b") == .ollamaQwen35B)

        for model in SmartAIModel.allCases {
            precondition(SmartAIModel.fromMenuTag(model.menuTag) == model)
            precondition(!model.displayName.isEmpty)
        }
        precondition(SmartAIModel.fromMenuTag(-1) == SmartAIModel.defaultModel)
        precondition(SmartAIModel.fromMenuTag(999) == SmartAIModel.defaultModel)
        print("SmartAIModelCheck passed")
    }
}
