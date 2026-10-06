import Foundation

// Stage B-1 覆盖诊断门禁:证明 SenseVoice 旁路的 completed 覆盖到停止点,
// 而不是只代表旧队列 drained。断言 provider 诊断记录:
//   - audioDurationMilliseconds     喂入音频总时长
//   - lastRecognizedAudioEndMilliseconds  最后一次成功识别覆盖到的音频时间
//   - tailGapMilliseconds           停止点与最后识别覆盖点之差(应很小)
// 见 docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md Task 1。

private struct FixedTextRecognizer: SenseVoiceSnapshotRecognizing {
    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        SenseVoiceSnapshotRecognitionOutput(text: "你好世界", tokens: ["你好", "世界"], tokenTimestamps: nil)
    }
}

@main
struct SenseVoiceCoverageDiagnosticsCheck {
    static func main() async throws {
        let sampleRate = 10
        let secondsOfAudio = 30
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-coverage",
            recognizer: FixedTextRecognizer(),
            configuration: .initial
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )
        let eventStream = await session.events()
        let collector = Task { () -> [TranscriptionEvent] in
            var events: [TranscriptionEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        try await session.start()
        for second in 0..<secondsOfAudio {
            try await session.append(AudioFrame(
                samples: Array(repeating: Float(second % 3) * 0.1 + 0.05, count: sampleRate),
                sampleRate: sampleRate,
                channelCount: 1,
                startFrame: Int64(second * sampleRate)
            ))
            await waitUntilProviderIdle(provider)
        }
        await session.finish()
        let events = await collector.value
        let diagnostics = await provider.diagnostics()

        precondition(
            events.contains { if case .completed = $0 { return true }; return false },
            "会话必须终结于 completed"
        )
        precondition(diagnostics.completedRecognitions > 0, "必须有成功识别")

        let expectedDurationMs = secondsOfAudio * 1_000
        precondition(
            diagnostics.audioDurationMilliseconds == expectedDurationMs,
            "audioDurationMilliseconds 应为 \(expectedDurationMs),实为 \(diagnostics.audioDurationMilliseconds)"
        )
        precondition(
            diagnostics.lastRecognizedAudioEndMilliseconds > 0,
            "lastRecognizedAudioEndMilliseconds 必须记录成功识别覆盖点"
        )
        precondition(
            diagnostics.lastRecognizedAudioEndMilliseconds <= diagnostics.audioDurationMilliseconds,
            "覆盖点不得超过音频总时长"
        )
        precondition(
            diagnostics.tailGapMilliseconds
                == max(0, diagnostics.audioDurationMilliseconds - diagnostics.lastRecognizedAudioEndMilliseconds),
            "tailGapMilliseconds 必须等于 时长 − 覆盖点"
        )
        precondition(
            diagnostics.tailGapMilliseconds <= 500,
            "停止后尾部覆盖差应 <= 500ms,实为 \(diagnostics.tailGapMilliseconds)ms"
        )

        print("SenseVoiceCoverageDiagnosticsCheck passed")
    }

    private static func waitUntilProviderIdle(_ provider: SenseVoiceSnapshotProvider) async {
        for _ in 0..<2_000 {
            let diagnostics = await provider.diagnostics()
            if diagnostics.currentActiveRecognitions == 0,
               diagnostics.currentPendingFast == 0,
               diagnostics.currentPendingCorrections == 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("SenseVoice snapshot provider did not drain scheduled work")
    }
}
