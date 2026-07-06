import Foundation

enum AppPaths {
    static let models = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typewhale-models")
}

@main
struct ManagedASRModelDownloaderProcessScanCheck {
    static func main() {
        let target = URL(fileURLWithPath: "/tmp/TypeWhale Models/funasr/.paraformer-zh-downloading", isDirectory: true)
        let unrelated = URL(fileURLWithPath: "/tmp/TypeWhale Models/funasr/.ct-punc-downloading", isDirectory: true)
        let veryLongCommand = String(repeating: "x", count: 120_000)
        let output = """
          101 /Library/Frameworks/Python.framework/Versions/3.10/bin/modelscope download --model a --local_dir \(target.path) --max-workers 4 \(veryLongCommand)
          202 /Library/Frameworks/Python.framework/Versions/3.10/bin/modelscope download --model b --local_dir \(unrelated.path) --max-workers 4
          303 /usr/bin/python something-else \(target.path)
        """

        let pids = ManagedASRModelDownloader.parseModelScopeDownloadPIDs(output: output, localDirectory: target)
        precondition(pids == [101], "Expected only the target ModelScope PID, got \(pids)")
        print("ManagedASRModelDownloaderProcessScanCheck passed")
    }
}
