import Foundation
@main struct ASRBenchmarkStoreCheck {
    static func main() throws {
        let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString); defer{try? FileManager.default.removeItem(at:root)}
        let store=ASRBenchmarkStore(rootURL:root)
        let result=ASRBenchmarkResult(id:UUID(),sampleID:"sample",candidateID:.senseVoiceInt8,hotwordSnapshot:["TypeWhale"],text:"TypeWhale 测试",coldLoadSeconds:1,firstInferenceSeconds:2,warmInferenceSeconds:0.5,audioDurationSeconds:2,peakRSSMB:100,createdAt:Date(timeIntervalSince1970:1))
        try store.save(result); let loaded=try store.loadAll(); precondition(loaded==[result]); precondition(result.realTimeFactor==0.25); precondition(result.hotwordHits==["TypeWhale"])
        try store.clear(); let cleared=try store.loadAll(); precondition(cleared.isEmpty); print("ASRBenchmarkStoreCheck passed")
    }
}
