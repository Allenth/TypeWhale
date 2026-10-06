import Foundation

@main
struct SherpaNativeTTSBackendCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        let pack = SherpaMeloTTSVoicePack(modelsRoot: modelsRoot)
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

        let fakeExecutable = root.appendingPathComponent("fake-sherpa-onnx-offline-tts")
        let marker = root.appendingPathComponent("args.txt")
        let script = """
        #!/usr/bin/env bash
        printf '%s\\n' "$@" > "\(marker.path)"
        while [[ "$#" -gt 0 ]]; do
          if [[ "$1" == --output-filename=* ]]; then
            printf 'RIFFfakeWAVE' > "${1#*=}"
            exit 0
          fi
          shift
        done
        exit 7
        """
        try Data(script.utf8).write(to: fakeExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeExecutable.path)

        let request = OpenClawVoiceSynthesisRequest(
            text: "测试 GitHub 和 MiniMax。",
            settings: OpenClawVoiceSettings(
                enabled: true,
                volume: 0.8,
                speechRate: 1.25,
                engine: .sherpaMelo44k,
                playbackPolicy: .finalReplyOnly,
                interruptPolicy: .stopPreviousAndPlayLatest
            ),
            workerScriptURL: URL(fileURLWithPath: "/tmp/unused-openclaw-worker.py"),
            modelsRoot: modelsRoot,
            outputURL: root.appendingPathComponent("out.wav")
        )

        let backend = SherpaNativeTTSBackend(executableURL: fakeExecutable, packDirectory: pack.directory)
        try backend.start(timeoutSeconds: 1)
        precondition(backend.isRunning)
        try backend.synthesize(request, timeoutSeconds: 5)
        precondition(FileManager.default.fileExists(atPath: request.outputURL.path))

        let args = try String(contentsOf: marker, encoding: .utf8)
        precondition(args.contains("--vits-model=\(pack.modelURL.path)"))
        precondition(args.contains("--vits-lexicon=\(pack.lexiconURL.path)"))
        precondition(args.contains("--vits-tokens=\(pack.tokensURL.path)"))
        precondition(args.contains("--vits-dict-dir=\(pack.dictDirectory.path)"))
        precondition(args.contains("--num-threads=4"))
        precondition(args.contains("--output-filename=\(request.outputURL.path)"))
        precondition(args.contains(request.speechText))

        backend.stop()
        precondition(!backend.isRunning)

        print("SherpaNativeTTSBackendCheck passed")
    }
}
