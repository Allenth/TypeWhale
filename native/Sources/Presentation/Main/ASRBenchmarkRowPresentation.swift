import Foundation

struct ASRBenchmarkRowPresentation: Equatable {
    let title:String, subtitle:String, readinessText:String, hotwordBadge:String, timingText:String, resultText:String
    let canRun:Bool, canCancel:Bool
    init(descriptor:ASRModelDescriptor,result:ASRBenchmarkResult?,isRunning:Bool){
        title=descriptor.displayName;subtitle=descriptor.engine.rawValue
        switch descriptor.readiness{case .ready:readinessText="可测试";case .validating:readinessText="验证中";case .unavailable(let why):readinessText="不可用：\(why)"}
        switch descriptor.hotwordStrategy{case .unsupported:hotwordBadge="不支持热词";case .nativeList,.nativeSpaceSeparated,.sherpaInline:hotwordBadge="原生热词";case .contextPrompt:hotwordBadge="上下文提示"}
        if let result{timingText=String(format:"冷载 %.2fs · 首次 %.2fs · 热态 %.2fs · RTF %.2f",result.coldLoadSeconds,result.firstInferenceSeconds,result.warmInferenceSeconds,result.realTimeFactor);resultText=result.text}else{timingText="尚未测试";resultText="—"}
        canRun=descriptor.readiness == .ready && !isRunning;canCancel=isRunning
    }
}
