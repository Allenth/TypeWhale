import Foundation

@main
struct SenseVoiceBoundaryCorrectionIntegrationCheck {
    static func main() async throws {
        let recognizer = BoundaryCorrectionRecognizer()
        let provider = SenseVoiceSnapshotProvider(
            id: "sensevoice-boundary-correction-check",
            recognizer: recognizer,
            configuration: SenseVoiceSnapshotProviderConfiguration(
                firstFastSeconds: 100,
                fastIntervalSeconds: 100,
                correctionIntervalSeconds: 6,
                maximumWindowSeconds: 14,
                maximumFastWindowSeconds: 3,
                maximumCorrectionWindowSeconds: 8,
                maximumServiceMilliseconds: 1_000,
                schedulerPolicy: .initial
            )
        )
        let session = TranscriptionSession(
            sessionID: TranscriptionSessionID(rawValue: UUID()),
            provider: provider
        )

        try await session.start()
        for second in 0..<14 {
            try await session.append(AudioFrame(
                samples: Array(repeating: Float(second), count: 10),
                sampleRate: 10,
                channelCount: 1,
                startFrame: Int64(second * 10)
            ))
            await waitUntilProviderIdle(provider)
        }

        let diagnostics = await provider.diagnostics()
        await session.cancel()
        precondition(
            diagnostics.boundaryCorrectionRequestedCount >= 1,
            "content conflict must schedule a boundary correction request"
        )
        precondition(
            diagnostics.boundaryCorrectionSucceededCount >= 1,
            "successful boundary correction recognition must be counted"
        )
        precondition(
            diagnostics.latestSeamConfidence == .boundaryCorrected,
            "successful boundary correction must report boundaryCorrected seam confidence"
        )
    }

    private static func waitUntilProviderIdle(_ provider: SenseVoiceSnapshotProvider) async {
        for _ in 0..<1_000 {
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

private actor BoundaryCorrectionRecognizer: SenseVoiceSnapshotRecognizing {
    private var callCount = 0

    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        callCount += 1
        switch callCount {
        case 1:
            return output("今天我们讨论公司")
        case 2:
            return output("功功能优化")
        default:
            return output("今天我们讨论功能优化")
        }
    }

    private func output(_ text: String) -> SenseVoiceSnapshotRecognitionOutput {
        SenseVoiceSnapshotRecognitionOutput(
            text: text,
            tokens: text.map(String.init),
            tokenTimestamps: nil
        )
    }
}
