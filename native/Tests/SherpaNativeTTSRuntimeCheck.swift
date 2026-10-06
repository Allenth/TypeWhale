import Foundation

@main
struct SherpaNativeTTSRuntimeCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let pack = SherpaMeloTTSVoicePack(modelsRoot: root)
        try FileManager.default.createDirectory(at: pack.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack.dictDirectory, withIntermediateDirectories: true)

        try Data("{}".utf8).write(to: pack.manifestURL)
        try Data("model".utf8).write(to: pack.modelURL)
        try Data("lexicon".utf8).write(to: pack.lexiconURL)
        try Data("tokens".utf8).write(to: pack.tokensURL)
        try Data("dict".utf8).write(to: pack.dictDirectory.appendingPathComponent("README.md"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("number.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("phone.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("date.fst"))

        precondition(pack.nativeRuntimeDirectory.path.hasSuffix("sherpa-vits-melo-tts-zh_en/runtime/native"))
        precondition(pack.nativeExecutableURL.lastPathComponent == "sherpa-onnx-offline-tts")

        do {
            _ = try pack.nativeExecutableURL()
            preconditionFailure("missing native executable must fail validation")
        } catch SherpaMeloTTSVoicePack.ValidationError.missingNativeRuntime { }

        let bundledRuntimeDirectory = root
            .appendingPathComponent("NativeTTS", isDirectory: true)
            .appendingPathComponent("sherpa", isDirectory: true)
        let bundledBinDirectory = bundledRuntimeDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledBinDirectory, withIntermediateDirectories: true)
        let bundledExecutable = bundledBinDirectory.appendingPathComponent("sherpa-onnx-offline-tts")
        FileManager.default.createFile(atPath: bundledExecutable.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledExecutable.path)
        let discoveredBundledExecutable = try pack.nativeExecutableURL(bundledRuntimeDirectory: bundledRuntimeDirectory)
        precondition(discoveredBundledExecutable == bundledExecutable, "bundled native runtime should be discoverable")

        try FileManager.default.createDirectory(at: pack.nativeRuntimeDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pack.nativeExecutableURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pack.nativeExecutableURL.path)

        let executable = try pack.nativeExecutableURL()
        precondition(executable.path == pack.nativeExecutableURL.path)
        try pack.validate(requireManifest: true)

        print("SherpaNativeTTSRuntimeCheck passed")
    }
}
