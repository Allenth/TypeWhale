import Foundation

@main
struct ManagedFunASRRuntimeCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        var runtime = ManagedFunASRRuntime(rootURL: root, moduleVerifier: { _ in true })
        precondition(runtime.state == .missing)

        try fileManager.createDirectory(at: runtime.pythonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: runtime.pythonURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.pythonURL.path)
        precondition(runtime.state == .invalid("运行环境版本标记缺失"))

        try runtime.writeVersionMarker()
        runtime = ManagedFunASRRuntime(rootURL: root, moduleVerifier: { _ in false })
        precondition(runtime.state == .invalid("运行环境依赖校验失败"))

        runtime = ManagedFunASRRuntime(rootURL: root, moduleVerifier: { url in url.path.hasSuffix("/python/bin/python3") })
        guard case .ready(let pythonURL) = runtime.state else {
            preconditionFailure("complete runtime must be ready")
        }
        precondition(pythonURL == runtime.pythonURL)

        try Data("wrong".utf8).write(to: runtime.versionMarkerURL)
        precondition(runtime.state == .invalid("运行环境版本不匹配"))
        print("ManagedFunASRRuntimeCheck passed")
    }
}
