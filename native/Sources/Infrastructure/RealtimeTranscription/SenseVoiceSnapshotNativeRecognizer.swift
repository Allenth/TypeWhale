import AVFAudio
import Foundation

/// Provider-local 的 Native bridge 适配器。
/// 临时 WAV 只存在于单次调用内部，回调或写入失败后都会删除。
final class SenseVoiceSnapshotNativeRecognizer: SenseVoiceSnapshotRecognizing, @unchecked Sendable {
    private let bridge: NativeSenseVoiceBridge
    private let configuration: ASRConfiguration
    private let fileQueue = DispatchQueue(
        label: "com.waykingah.typewhale.shadow-sensevoice-files",
        qos: .userInitiated
    )

    init(
        bridge: NativeSenseVoiceBridge,
        configuration: ASRConfiguration
    ) {
        self.bridge = bridge
        self.configuration = configuration
    }

    func recognize(
        samples: [Float],
        sampleRate: Int
    ) async throws -> SenseVoiceSnapshotRecognitionOutput {
        try await withCheckedThrowingContinuation { continuation in
            fileQueue.async { [bridge, configuration] in
                let audioURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TypeWhaleShadowSenseVoice", isDirectory: true)
                    .appendingPathComponent("\(UUID().uuidString).wav")
                do {
                    try FileManager.default.createDirectory(
                        at: audioURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Self.writeWAV(
                        samples: samples,
                        sampleRate: sampleRate,
                        to: audioURL
                    )
                    bridge.transcribeDetailed(
                        audio: audioURL,
                        configuration: configuration
                    ) { result in
                        try? FileManager.default.removeItem(at: audioURL)
                        continuation.resume(with: result.map { native in
                            SenseVoiceSnapshotRecognitionOutput(
                                text: native.text,
                                tokens: native.tokens,
                                tokenTimestamps: native.validatedTokenTimestamps
                            )
                        })
                    }
                } catch {
                    try? FileManager.default.removeItem(at: audioURL)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func writeWAV(
        samples: [Float],
        sampleRate: Int,
        to destination: URL
    ) throws {
        guard sampleRate > 0,
              !samples.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(sampleRate),
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0] else {
            throw SenseVoiceSnapshotProviderError.invalidAudioFrame
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: source.count)
        }
        let file = try AVAudioFile(forWriting: destination, settings: format.settings)
        try file.write(from: buffer)
    }
}
