import Foundation

@main
struct SmartAIModelCheck {
    static func main() {
        precondition(SmartAIModel.defaultModel == .deepSeekV4Flash)
        precondition(SmartAIModel.allCases.map(\.rawValue) == [
            "deepseek-v4-flash",
        ])
        precondition(SmartAIModel.deepSeekV4Flash.provider == .deepSeek)
        precondition(SmartAIModel.deepSeekV4Flash.supportsUsageSummary)
        precondition(SmartAIModel.fromStoredRawValue("MiniMax-M2") == .deepSeekV4Flash)
        precondition(SmartAIModel.fromStoredRawValue("MiniMax-M2.5-highspeed") == .deepSeekV4Flash)

        for model in SmartAIModel.allCases {
            precondition(SmartAIModel.fromMenuTag(model.menuTag) == model)
            precondition(!model.displayName.isEmpty)
        }
        precondition(SmartAIModel.fromMenuTag(-1) == SmartAIModel.defaultModel)
        precondition(SmartAIModel.fromMenuTag(999) == SmartAIModel.defaultModel)
        print("SmartAIModelCheck passed")
    }
}
