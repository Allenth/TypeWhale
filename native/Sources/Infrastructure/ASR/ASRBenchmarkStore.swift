import Foundation

struct ASRBenchmarkStore {
    let rootURL: URL
    private var resultsURL: URL { rootURL.appendingPathComponent("results.json") }
    func loadAll() throws -> [ASRBenchmarkResult] {
        guard FileManager.default.fileExists(atPath:resultsURL.path) else{return []}
        return try JSONDecoder().decode([ASRBenchmarkResult].self,from:Data(contentsOf:resultsURL))
    }
    func save(_ result:ASRBenchmarkResult) throws {
        try FileManager.default.createDirectory(at:rootURL,withIntermediateDirectories:true)
        var values=try loadAll(); values.removeAll{$0.sampleID==result.sampleID && $0.candidateID==result.candidateID && $0.hotwordSnapshot==result.hotwordSnapshot}; values.append(result)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(values).write(to:resultsURL,options:.atomic)
    }
    func clear() throws {
        guard FileManager.default.fileExists(atPath:rootURL.path) else{return}
        try FileManager.default.removeItem(at:rootURL)
    }
}
