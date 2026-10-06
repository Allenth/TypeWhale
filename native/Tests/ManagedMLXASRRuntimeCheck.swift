import Foundation

@main
struct ManagedMLXASRRuntimeCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = ManagedMLXASRRuntime(rootURL: root, moduleVerifier: { _ in true })
        precondition(missing.state == .missing)
        try FileManager.default.createDirectory(at: missing.pythonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: missing.pythonURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: missing.pythonURL.path)
        precondition(missing.state == .invalid("运行环境版本标记缺失"))
        try missing.writeVersionMarker()
        precondition(missing.state == .ready(missing.pythonURL))
        let invalid = ManagedMLXASRRuntime(rootURL: root, moduleVerifier: { _ in false })
        precondition(invalid.state == .invalid("运行环境依赖校验失败"))
        print("ManagedMLXASRRuntimeCheck passed")
    }
}
