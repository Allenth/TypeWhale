import Foundation

@main
struct RemoteADPCMDecoderCheck {
    static func main() {
        startsFromTheDeclaredStateAndUsesHighNibbleFirst()
        resetsPredictorAndStepIndex()
        clampsPredictorAndStepIndex()
        print("RemoteADPCMDecoderCheck passed")
    }

    private static func startsFromTheDeclaredStateAndUsesHighNibbleFirst() {
        var decoder = RemoteADPCMDecoder()
        decoder.reset(predictor: 0, stepIndex: 0)
        precondition(decoder.decode([0x12]) == [1, 4])

        decoder.reset(predictor: 0, stepIndex: 0)
        precondition(decoder.decode([0x87]) == [0, 11])
    }

    private static func resetsPredictorAndStepIndex() {
        var decoder = RemoteADPCMDecoder()
        decoder.reset(predictor: 100, stepIndex: 10)
        precondition(decoder.decode([0xF0]) == [66, 71])
    }

    private static func clampsPredictorAndStepIndex() {
        var decoder = RemoteADPCMDecoder()
        decoder.reset(predictor: Int16.max, stepIndex: 255)
        let samples = decoder.decode(Array(repeating: UInt8(0x77), count: 32))
        precondition(samples.allSatisfy { $0 <= Int16.max })
        precondition(samples.last == Int16.max)
    }
}
