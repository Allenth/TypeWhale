import Foundation

@main
struct TTSReadingLabServiceCheck {
    static func main() throws {
        let workerURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let pythonURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("typewhale-tts-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputRoot) }

        let modelDirectory = outputRoot.appendingPathComponent("fake-model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let model = TTSLabModel(
            id: "fake",
            displayName: "Fake",
            tier: 1,
            runtime: .sherpaONNX,
            capabilities: .basic,
            directory: modelDirectory,
            defaultSpeakerID: 50
        )
        let player = FakePlayer()
        let voice = TTSLabVoice(
            id: "test-voice",
            displayName: "Test Voice",
            detail: "测试",
            group: .qwen,
            speakerID: nil,
            isDefault: true
        )
        let service = TTSReadingLabService(
            outputRoot: outputRoot,
            player: player,
            callbackQueue: .global(),
            workerFactory: {
                TTSLabWorkerClient(
                    pythonURL: pythonURL,
                    workerURL: workerURL,
                    fakeDelay: 0
                )
            }
        )

        let completed = DispatchSemaphore(value: 0)
        var states: [TTSReadingLabState] = []
        service.onStateChange = { state in
            states.append(state)
            if case .completed = state { completed.signal() }
        }
        service.start(text: "你好 TypeWhale", model: model, voice: voice)
        precondition(completed.wait(timeout: .now() + 5) == .success)
        precondition(states.contains { if case .preparing = $0 { return true }; return false })
        precondition(states.contains { if case .generating = $0 { return true }; return false })
        precondition(states.contains { if case .playing = $0 { return true }; return false })
        precondition(player.playCount == 1)
        guard case .completed(let metrics, let outputURL, let actualVoiceID) = states.last else {
            preconditionFailure("expected completed state")
        }
        precondition(actualVoiceID == voice.id)
        precondition(metrics.audioSeconds > 0)
        precondition(FileManager.default.fileExists(atPath: outputURL.path))

        service.stop()
        Thread.sleep(forTimeInterval: 0.1)
        guard case .stopped = states.last else {
            preconditionFailure("expected stopped state")
        }
        precondition(player.stopCount >= 1)
        print("TTSReadingLabServiceCheck passed")
    }
}

private final class FakePlayer: TTSLabAudioPlaying {
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func play(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        playCount += 1
        completion(.success(()))
    }

    func stop() {
        stopCount += 1
    }
}
