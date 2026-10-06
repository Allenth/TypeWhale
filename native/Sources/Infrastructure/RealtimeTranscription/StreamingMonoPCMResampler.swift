import Foundation

enum StreamingMonoPCMResamplerError: Error, Sendable, Equatable {
    case invalidFrame
}

/// Stateful, bounded mono PCM normalization for provider-owned audio timelines.
/// Downsampling uses area-weighted averaging rather than relabeling or point decimation.
struct StreamingMonoPCMResampler: Sendable {
    private let outputSampleRate: Int
    private var inputSampleRate: Int?
    private var expectedNextSourceFrame: Int64?
    private var sourceBuffer: [Float] = []
    private var sourceBufferStart: Int64 = 0
    private var totalSourceSamples: Int64 = 0
    private var nextSourcePosition: Double = 0
    private var totalOutputSamples: Int64 = 0

    init(outputSampleRate: Int = 16_000) {
        precondition(outputSampleRate > 0)
        self.outputSampleRate = outputSampleRate
    }

    mutating func append(_ frame: AudioFrame) throws -> AudioFrame? {
        guard frame.sampleRate > 0,
              frame.channelCount == 1,
              !frame.samples.isEmpty else {
            throw StreamingMonoPCMResamplerError.invalidFrame
        }
        if let inputSampleRate {
            guard inputSampleRate == frame.sampleRate,
                  expectedNextSourceFrame == frame.startFrame else {
                throw StreamingMonoPCMResamplerError.invalidFrame
            }
        } else {
            inputSampleRate = frame.sampleRate
            expectedNextSourceFrame = frame.startFrame
        }
        guard expectedNextSourceFrame == frame.startFrame else {
            throw StreamingMonoPCMResamplerError.invalidFrame
        }
        expectedNextSourceFrame = frame.startFrame + Int64(frame.samples.count)

        if sourceBuffer.isEmpty { sourceBufferStart = totalSourceSamples }
        sourceBuffer.append(contentsOf: frame.samples)
        totalSourceSamples += Int64(frame.samples.count)

        let sourceSamplesPerOutput = Double(frame.sampleRate) / Double(outputSampleRate)
        var output: [Float] = []
        output.reserveCapacity(max(
            1,
            Int(ceil(Double(frame.samples.count) / sourceSamplesPerOutput))
        ))

        while nextSourcePosition + sourceSamplesPerOutput <= Double(totalSourceSamples) + 1e-9 {
            let windowEnd = nextSourcePosition + sourceSamplesPerOutput
            var cursor = nextSourcePosition
            var weightedSum: Double = 0
            while cursor < windowEnd - 1e-12 {
                let sourceIndex = Int64(floor(cursor))
                let segmentEnd = min(windowEnd, Double(sourceIndex + 1))
                let bufferIndex = Int(sourceIndex - sourceBufferStart)
                guard sourceBuffer.indices.contains(bufferIndex) else {
                    throw StreamingMonoPCMResamplerError.invalidFrame
                }
                weightedSum += Double(sourceBuffer[bufferIndex]) * (segmentEnd - cursor)
                cursor = segmentEnd
            }
            output.append(Float(weightedSum / sourceSamplesPerOutput))
            nextSourcePosition = windowEnd
        }

        let firstNeededSource = Int64(floor(nextSourcePosition))
        let discardCount = min(
            sourceBuffer.count,
            max(0, Int(firstNeededSource - sourceBufferStart))
        )
        if discardCount > 0 {
            sourceBuffer.removeFirst(discardCount)
            sourceBufferStart += Int64(discardCount)
        }

        guard !output.isEmpty else { return nil }
        let outputStartFrame = totalOutputSamples
        totalOutputSamples += Int64(output.count)
        return AudioFrame(
            samples: output,
            sampleRate: outputSampleRate,
            channelCount: 1,
            startFrame: outputStartFrame
        )
    }

    mutating func reset() {
        self = StreamingMonoPCMResampler(outputSampleRate: outputSampleRate)
    }
}
